import 'dart:async';
import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

class VmClient {
  VmClient._(this._service, this._isolateId);

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

  static Future<VmClient> connect(Uri uri) async {
    final wsUri = _toWebSocketUri(uri);
    final service = await vmServiceConnectUri(wsUri.toString());
    final isolateId = await _findQaIsolate(service);
    return VmClient._(service, isolateId);
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
    final stringArgs = <String, String>{};
    args?.forEach((k, v) => stringArgs[k] = v is String ? v : jsonEncode(v));
    try {
      return await rawCallExtension(name, stringArgs);
    } catch (e) {
      if (!_isStaleIsolateError(e)) rethrow;
      try {
        await rebindIsolate();
      } catch (_) {
        throw StateError(
          'QA probe isolate is gone and could not be re-resolved. The app '
          'likely hot-restarted without re-registering ext.qa.* (is '
          'AgentWiresProbe.install() in main()?) or it exited. Re-run '
          'boot_app to recover.',
        );
      }
      return await rawCallExtension(name, stringArgs);
    }
  }

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
    if (await _boundIsolateHasQa()) return true;
    try {
      _isolateId = await resolveQaIsolate();
      return true;
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
