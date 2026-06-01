import 'dart:async';
import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Thrown when the VM-service connection itself is gone — disposed, closed, or
/// hung past [VmClient.callTimeout] on a dead/half-open socket. Distinct from a
/// stale-isolate error (recoverable via rebind): the whole connection is dead,
/// so the only recovery is to reattach or reboot (`boot_app`). Surfacing this
/// fast is what stops a lost connection from wedging every subsequent tool
/// call for minutes.
class VmConnectionLostException implements Exception {
  VmConnectionLostException(this.message);
  final String message;
  @override
  String toString() => 'VmConnectionLostException: $message';
}

class VmClient {
  VmClient._(this._service, this._isolateId) {
    _wireConnectionState();
  }

  /// Named constructor for test subclasses. Initialises fields with no-op
  /// values; subclasses should override the [rawCallExtension] /
  /// [resolveQaIsolate] seams.
  VmClient.test()
      : _service = VmService(const Stream.empty(), (_) {}),
        _isolateId = '';

  final VmService _service;

  // Mutable: a hot restart tears down the QA isolate and spins up a new one
  // with a different id. We re-resolve and rebind ([rebindIsolate]) instead
  // of holding a now-collected isolate id forever.
  String _isolateId;

  /// The currently-bound QA isolate id. Exposed for diagnostics/tests.
  String get isolateId => _isolateId;

  // Latched once the underlying connection is known to be dead (the socket
  // closed, a call came back "disposed", or a call hung past [callTimeout]).
  // Once set, every call fails fast instead of awaiting a corpse.
  bool _connectionLost = false;

  /// True when the VM-service connection is known to be gone. After this flips,
  /// calls fail immediately with [VmConnectionLostException] — recovery means a
  /// fresh attach (`boot_app`), not a retry against the dead socket.
  bool get isConnectionLost => _connectionLost;

  /// Upper bound on a single VM-service call. A half-open socket can leave the
  /// RPC future pending forever; without this the session wedges for minutes.
  /// Generous enough for a heavy snapshot, short enough to recover quickly.
  /// Overridable as a test seam.
  @visibleForTesting
  Duration get callTimeout => const Duration(seconds: 30);

  // Listens for the connection closing so a cleanly-dropped socket latches
  // [_connectionLost] the instant it dies, rather than on the next timeout.
  // Only wired for real connections (the [VmClient._] path) — the `.test()`
  // constructor's empty stream would otherwise complete onDone immediately.
  void _wireConnectionState() {
    _service.onDone.then((_) {
      _connectionLost = true;
    }).catchError((_) {});
  }

  static Future<VmClient> connect(Uri uri) async {
    final wsUri = _toWebSocketUri(uri);
    final service = await vmServiceConnectUri(wsUri.toString());
    // Bind with no isolate yet, resume anything paused at start, THEN locate
    // the QA isolate. Order matters: an isolate paused at start (a physical
    // iPhone launched via `devicectl --start-stopped`) hasn't run main() yet,
    // so the probe isn't registered and _findQaIsolate would time out — and
    // the app would sit frozen on screen while status read "ready" (#3).
    final client = VmClient._(service, '');
    await client.resumePausedIsolates();
    client._isolateId = await _findQaIsolate(service);
    return client;
  }

  /// Walks every isolate looking for one that has registered an `ext.qa.*`
  /// extension. Polls for up to 10 s because extension registration races
  /// with app startup.
  static Future<String> _findQaIsolate(VmService service) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    String? lastNonQaIsolateId;
    while (DateTime.now().isBefore(deadline)) {
      final vm = await service.getVM();
      for (final ref in vm.isolates ?? const <IsolateRef>[]) {
        final id = ref.id;
        if (id == null) continue;
        try {
          final full = await service.getIsolate(id);
          final exts = full.extensionRPCs ?? const <String>[];
          if (exts.any((e) => e.startsWith('ext.qa.'))) return id;
          lastNonQaIsolateId = id;
        } catch (_) {
          // Skip isolates that fail to load (race with isolate exit).
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (lastNonQaIsolateId != null) {
      throw StateError(
        'no isolate has ext.qa.* extensions registered — is '
        'AgentWiresProbe.install() called in main()? Falling back is unsafe '
        'because tool calls would silently target the wrong isolate.',
      );
    }
    throw StateError('no isolates in VM');
  }

  /// Calls an `ext.qa.*` service extension on the bound QA isolate.
  ///
  /// Self-healing: if the bound isolate has been collected (the classic
  /// symptom after a hot restart — a `[Sentinel kind: Collected]` error), we
  /// re-resolve the live QA isolate once and retry, so a single tool call
  /// recovers transparently instead of the whole session wedging.
  Future<Map<String, dynamic>> callExtension(
    String name, [
    Map<String, dynamic>? args,
  ]) async {
    // Already-dead connection: don't even touch the socket — fail instantly.
    if (_connectionLost) throw _connectionLostError(name);
    final stringArgs = <String, String>{};
    args?.forEach((k, v) => stringArgs[k] = v is String ? v : jsonEncode(v));
    try {
      return await _timedRawCall(name, stringArgs);
    } catch (e) {
      // A dead connection is NOT a stale isolate: rebinding re-resolves over
      // the same dead socket and would hang again. Latch and fail fast.
      if (_isConnectionLostError(e)) {
        _connectionLost = true;
        throw _connectionLostError(name);
      }
      if (!_isStaleIsolateError(e)) rethrow;
      try {
        await rebindIsolate();
      } catch (rebindError) {
        if (_isConnectionLostError(rebindError)) {
          _connectionLost = true;
          throw _connectionLostError(name);
        }
        throw StateError(
          'QA probe isolate is gone and could not be re-resolved. The app '
          'likely hot-restarted without re-registering ext.qa.* (is '
          'AgentWiresProbe.install() in main()?) or it exited. Re-run '
          'boot_app to recover.',
        );
      }
      return await _timedRawCall(name, stringArgs);
    }
  }

  /// Wraps [rawCallExtension] with [callTimeout]. A timeout means the socket is
  /// dead (or the probe is unresponsive past any reasonable bound), so we latch
  /// the connection as lost and translate to [VmConnectionLostException] — the
  /// next call then fails instantly instead of eating another full timeout.
  Future<Map<String, dynamic>> _timedRawCall(
    String name,
    Map<String, String> args,
  ) async {
    try {
      return await rawCallExtension(name, args).timeout(callTimeout);
    } on TimeoutException {
      _connectionLost = true;
      throw VmConnectionLostException(
        'VM-service call "$name" exceeded ${callTimeout.inSeconds}s — the '
        'connection appears dead. Reattach or reboot with boot_app.',
      );
    }
  }

  VmConnectionLostException _connectionLostError(String name) =>
      VmConnectionLostException(
        'VM-service connection lost (call "$name"). Reattach or reboot with '
        'boot_app.',
      );

  /// The low-level service-extension call against the currently-bound isolate.
  /// Seam for tests and for the retry wrapper in [callExtension].
  @visibleForTesting
  Future<Map<String, dynamic>> rawCallExtension(
    String name,
    Map<String, String> args,
  ) async {
    final response = await _service.callServiceExtension(
      name,
      isolateId: _isolateId,
      args: args,
    );
    final json = response.json ?? const <String, dynamic>{};
    if (json['result'] is String) {
      try {
        return jsonDecode(json['result'] as String) as Map<String, dynamic>;
      } catch (_) {
        return json;
      }
    }
    return Map<String, dynamic>.from(json);
  }

  /// Re-resolves the live QA isolate and rebinds to it. Used to recover from
  /// a hot restart (which collects the old isolate and creates a new one).
  Future<void> rebindIsolate() async {
    _isolateId = await resolveQaIsolate();
  }

  /// Finds the isolate currently exposing `ext.qa.*`. Seam over the static
  /// [_findQaIsolate] so tests can simulate a restart without a live VM.
  @visibleForTesting
  Future<String> resolveQaIsolate() => _findQaIsolate(_service);

  /// True when the probe is reachable. Tries the bound isolate first; if it's
  /// been collected (post hot-restart), re-resolves and rebinds to the new
  /// isolate so `app_status` reports the truth and the next call is fast.
  Future<bool> isProbeAlive() async {
    // A dead connection can't host a live probe — and re-probing it would just
    // hang. Answer immediately so app_status stays responsive.
    if (_connectionLost) return false;
    if (await _boundIsolateHasQa()) return true;
    try {
      _isolateId = await resolveQaIsolate();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The probe's self-reported version (from `ext.qa.ping`), or null if the
  /// probe is unreachable or predates version reporting. Never throws — a
  /// version check must not be able to break a tool call. Used to warn on
  /// probe/server version skew (#6).
  Future<String?> probeVersion() async {
    try {
      final res = await callExtension('ext.qa.ping');
      final v = res['probe_version'];
      return v is String ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Ids of every isolate currently paused at start. Bounded by [callTimeout]
  /// so a dead socket can't make this hang. Seam for tests.
  @visibleForTesting
  Future<List<String>> pausedAtStartIsolates() async {
    final vm = await _service.getVM().timeout(callTimeout);
    final ids = <String>[];
    for (final ref in vm.isolates ?? const <IsolateRef>[]) {
      final id = ref.id;
      if (id == null) continue;
      try {
        final iso = await _service.getIsolate(id).timeout(callTimeout);
        if (iso.pauseEvent?.kind == EventKind.kPauseStart) ids.add(id);
      } catch (_) {
        // Skip isolates that fail to load (race with isolate exit).
      }
    }
    return ids;
  }

  /// Resumes a single isolate by id. Seam for tests.
  @visibleForTesting
  Future<void> resumeIsolate(String id) => _service.resume(id);

  /// Resumes any isolate paused at start so the app actually runs instead of
  /// sitting frozen — the `devicectl --start-stopped` symptom where the app
  /// looks broken while status reports ready (#3). Best-effort and bounded; a
  /// failure here must never block attach.
  Future<void> resumePausedIsolates() async {
    if (_connectionLost) return;
    List<String> paused;
    try {
      paused = await pausedAtStartIsolates();
    } catch (_) {
      return;
    }
    for (final id in paused) {
      try {
        await resumeIsolate(id).timeout(callTimeout);
      } catch (_) {
        // A resume that fails leaves the isolate paused; app_status surfaces
        // that via isPausedAtStart so the agent isn't left guessing.
      }
    }
  }

  /// True when any isolate is still paused at start — i.e. a resume could not
  /// be confirmed and the app is likely frozen. Surfaced by `app_status` so a
  /// paused launch is reported instead of a misleading "ready" (#3).
  Future<bool> isPausedAtStart() async {
    if (_connectionLost) return false;
    try {
      return (await pausedAtStartIsolates()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _boundIsolateHasQa() async {
    if (_isolateId.isEmpty) return false;
    try {
      final iso = await _service.getIsolate(_isolateId);
      return (iso.extensionRPCs ?? const <String>[])
          .any((e) => e.startsWith('ext.qa.'));
    } catch (_) {
      return false;
    }
  }

  /// Recognises the errors the VM service raises when a tool call targets an
  /// isolate that no longer exists (collected after a hot restart, expired,
  /// etc.). Matched on type and message so it survives vm_service version
  /// churn — the user-visible string was `[Sentinel kind: Collected, …]`.
  /// Recognises errors that mean the whole connection is dead (not just the
  /// bound isolate): the VM service was disposed, the WebSocket closed, or a
  /// JSON-RPC internal error (-32603) was raised — the symptoms from the field
  /// report. Matched on the message so it survives vm_service version churn.
  static bool _isConnectionLostError(Object e) {
    if (e is VmConnectionLostException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('connection disposed') ||
        s.contains('service disposed') ||
        s.contains('connection closed') ||
        s.contains('client is closed') ||
        s.contains('websocket') ||
        s.contains('-32603');
  }

  static bool _isStaleIsolateError(Object e) {
    if (e is SentinelException) return true;
    final s = e.toString();
    return s.contains('Sentinel') ||
        s.contains('Collected') ||
        s.contains('Expired') ||
        s.contains('isolate must be runnable') ||
        s.contains('Cannot find isolate') ||
        s.contains('isolate not found');
  }

  /// Asks the VM to reload changed sources into the QA isolate (the Dart
  /// equivalent of Flutter's hot reload). Returns `{success: bool}`.
  ///
  /// Note: Flutter normally couples a reload with a `reassemble` that
  /// rebuilds the widget tree. This call only does the source swap — for
  /// the full Flutter hot reload semantics, use [FlutterRunner.hotReload]
  /// instead (only available in lazy/run mode).
  Future<Map<String, dynamic>> reloadSources() async {
    final report = await _service.reloadSources(_isolateId);
    return {'success': report.success ?? false};
  }

  Future<void> dispose() async {
    await _service.dispose();
  }

  /// `flutter run`/`flutter test --machine` prints the VM service URI as
  /// `http(s)://host:port/<auth>/`. The Dart VM service WebSocket lives at
  /// `ws(s)://host:port/<auth>/ws`. Accept both shapes from callers.
  static Uri _toWebSocketUri(Uri uri) {
    final scheme = switch (uri.scheme) {
      'http' => 'ws',
      'https' => 'wss',
      'ws' || 'wss' => uri.scheme,
      _ => throw ArgumentError(
          'VM service URI must be http(s) or ws(s), got: $uri',
        ),
    };
    final segments = [...uri.pathSegments.where((s) => s.isNotEmpty)];
    if (segments.isEmpty || segments.last != 'ws') segments.add('ws');
    return uri.replace(scheme: scheme, pathSegments: segments);
  }
}
