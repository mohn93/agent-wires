import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import '../runner/flutter_runner.dart';
import '../vm/client.dart';

enum AppState { idle, booting, ready, exited }

/// Owns the lifecycle of "the app under test" — its `flutter run --machine`
/// subprocess and the [VmClient] attached to it.
///
/// Two construction modes:
///   * [AppSession.lazy] — owns a [FlutterRunner], boots on first
///     [ensureReady]. Used by `agent_wires_mcp run`.
///   * [AppSession.attached] — wraps an externally-connected [VmClient]
///     (e.g. `agent_wires_mcp serve --attach <uri>`); always ready.
///
/// MCP tools should call [ensureReady] at the top of their handler instead of
/// holding a [VmClient] directly. That keeps the MCP handshake instant and
/// defers the slow `flutter run` cold start until a tool is actually invoked.
class AppSession {
  AppSession.lazy({
    required String workingDirectory,
    String? deviceId,
    List<String> flutterArgs = const <String>[],
    this.bootTimeout = defaultBootTimeout,
  })  : _workingDirectory = workingDirectory,
        _deviceId = deviceId,
        _flutterArgs = flutterArgs,
        _attached = false;

  /// Default upper bound on a single `flutter run` boot. Large apps
  /// (firebase, native plugins) can take well past 5 min on a cold compile;
  /// `boot_app(timeout_minutes)` raises it further for a known-cold cache.
  static const Duration defaultBootTimeout = Duration(minutes: 10);

  /// How long [ensureReady] waits for `flutter run` to report a VM service
  /// URI before giving up. Mutable so `boot_app(timeout_minutes)` can raise
  /// it; the new value sticks for the rest of the session.
  Duration bootTimeout;

  AppSession.attached(VmClient vm)
      : _workingDirectory = null,
        _deviceId = null,
        _flutterArgs = const <String>[],
        _attached = true,
        bootTimeout = defaultBootTimeout,
        _vm = vm,
        _state = AppState.ready;

  final String? _workingDirectory;
  // Mutable so the agent can pick a device per-boot (e.g. after calling
  // list_devices and asking the user). Set via [selectDevice] before
  // ensureReady.
  String? _deviceId;
  final List<String> _flutterArgs;
  final bool _attached;

  FlutterRunner? _runner;
  VmClient? _vm;
  AppState _state = AppState.idle;
  String? _lastError;
  // Cached separately from the runner so it survives runner disposal — the
  // diagnostic value of "what was flutter doing when it died?" is gone if
  // we read it through the (now-null) runner.
  String? _latestProgress;
  Future<VmClient>? _bootFuture;
  Future<VmClient>? _reattachFuture;

  AppState get state => _state;
  String? get lastError => _lastError;

  /// True for `serve --attach` sessions, which wrap a VM client they did not
  /// create and therefore cannot reattach or reboot on their own.
  bool get isAttached => _attached;

  /// True when the session looks `ready` but its VM-service socket is known
  /// to be dead. `app_status` surfaces this so the agent knows the next
  /// `boot_app` will reattach rather than "do nothing".
  bool get isConnectionLost => _vm?.isConnectionLost ?? false;

  /// Whether [ensureReady] should try to reattach instead of returning the
  /// cached client: only a `ready` session whose connection was latched as
  /// lost. Pure + testable.
  @visibleForTesting
  static bool needsReattach({
    required AppState state,
    required bool connectionLost,
  }) =>
      state == AppState.ready && connectionLost;
  String? get deviceId => _deviceId;
  Uri? get vmServiceUri =>
      _state == AppState.ready ? _runner?.vmServiceUriOrNull : null;

  /// The latest progress message from `flutter run --machine` (Xcode build
  /// step, Pod install line, dart compile progress). Cached on the session
  /// so it persists after the runner is disposed — that's exactly when the
  /// agent needs to see what flutter was doing when the boot failed.
  String? get latestProgress => _latestProgress;

  /// Selects a device for the next boot. Only valid in lazy mode and when
  /// the session is not currently `ready` (the existing flutter process
  /// can't be retargeted to a different device — caller must `stop_app`
  /// first). Passing null clears the pin and lets flutter pick.
  void selectDevice(String? deviceId) {
    if (_attached) {
      throw StateError('attached AppSession has no device to select');
    }
    if (_state == AppState.ready) {
      throw StateError(
        'cannot change device while the app is running; call stop_app first',
      );
    }
    _deviceId = deviceId;
  }

  /// Whether the QA probe is actually reachable right now — distinct from
  /// [state], which only tracks the `flutter run` process. After a hot
  /// restart the process stays up (`state == ready`) but the probe lives in a
  /// fresh isolate; this asks the [VmClient], which re-resolves and rebinds if
  /// the previously-bound isolate was collected. `app_status` surfaces this so
  /// the agent can tell "process alive but probe gone" from "all good".
  Future<bool> isProbeAlive() async {
    if (_state != AppState.ready || _vm == null) return false;
    return _vm!.isProbeAlive();
  }

  /// The version reported by the attached probe, or null when not ready / not
  /// reachable. Surfaced by `app_status` for version-skew warnings (#6).
  Future<String?> probeVersion() async {
    if (_state != AppState.ready || _vm == null) return null;
    return _vm!.probeVersion();
  }

  /// Whether the app is frozen because an isolate is still paused at start
  /// (the `devicectl --start-stopped` symptom). Surfaced by `app_status` so a
  /// frozen launch is reported instead of a misleading "ready" (#3).
  Future<bool> isPausedAtStart() async {
    if (_state != AppState.ready || _vm == null) return false;
    return _vm!.isPausedAtStart();
  }

  /// Whether a `boot_app(device_id)` should force-stop the current session
  /// before retargeting. Only a *running lazy* session bound to a *different*
  /// device needs it — attached sessions can't switch device, and an idle /
  /// already-on-this-device session has nothing to tear down. Pure + testable.
  @visibleForTesting
  static bool shouldForceStopForDevice({
    required bool attached,
    required AppState state,
    required String? currentDevice,
    required String requestedDevice,
  }) =>
      !attached && state == AppState.ready && currentDevice != requestedDevice;

  /// Pins [deviceId] for the next boot, force-stopping first when the app is
  /// already running on a different device. This lets `boot_app(device_id)`
  /// switch devices on its own instead of requiring the agent to call
  /// `stop_app` — which used to deadlock when the VM-service was already dead
  /// (the #1/#6 deadlock). `dispose` is bounded, so the stop can't wedge.
  Future<void> prepareDevice(String deviceId) async {
    if (shouldForceStopForDevice(
      attached: _attached,
      state: _state,
      currentDevice: _deviceId,
      requestedDevice: deviceId,
    )) {
      await dispose();
    }
    selectDevice(deviceId);
  }

  /// Returns the connected [VmClient]. If the session is lazy and hasn't been
  /// booted yet (or a previous boot timed out / was stopped), this kicks off
  /// `flutter run --machine`, waits for the VM service URI, and attaches.
  /// Concurrent callers share one boot future.
  ///
  /// Lazy sessions can recover from [AppState.exited] — we own the flutter
  /// command + project config and can simply re-boot. Attached sessions
  /// stay terminal because we have no way to reconnect to a process we
  /// don't own; the caller must construct a new AppSession.
  Future<VmClient> ensureReady() async {
    if (_state == AppState.ready && _vm != null) {
      if (!needsReattach(
          state: _state, connectionLost: _vm!.isConnectionLost)) {
        return _vm!;
      }
      // The socket died but the flutter process may well be alive (a
      // transient VM-service drop). Previously this branch handed back the
      // dead client forever and `boot_app` reported "ready" without
      // reconnecting — the only way out was stop_app + boot_app.
      if (_attached) {
        throw StateError(
          'VM-service connection lost and an attached AppSession cannot '
          'reconnect on its own. Restart the MCP server against the app\'s '
          'current VM service URI.',
        );
      }
      // Concurrent tools racing after a socket drop (app_status polling while
      // snapshot runs) must share one reconnect, like boots share _bootFuture.
      final inFlight = _reattachFuture;
      if (inFlight != null) return inFlight;
      final future = _reattachOrReboot();
      _reattachFuture = future;
      try {
        return await future;
      } finally {
        _reattachFuture = null;
      }
    }
    if (_state == AppState.exited) {
      if (_attached) {
        throw StateError(
          'attached AppSession is exited and cannot be revived. The flutter '
          'process must be restarted externally and a new AppSession '
          'constructed with the new VM service URI.',
        );
      }
      // Lazy mode: reset to idle and let the boot path below run again.
      _state = AppState.idle;
      _lastError = null;
      _runner = null;
      _vm = null;
    }
    if (_attached) {
      throw StateError('attached AppSession has no VmClient');
    }
    final existing = _bootFuture;
    if (existing != null) return existing;
    final future = _boot();
    _bootFuture = future;
    try {
      return await future;
    } finally {
      _bootFuture = null;
    }
  }

  /// Re-opens the VM-service socket of the still-running flutter process.
  /// Falls back to a full reboot when the process (or its URI) is gone.
  Future<VmClient> _reattachOrReboot() async {
    final uri = _runner?.vmServiceUriOrNull;
    if (uri != null) {
      try {
        try {
          await _vm?.dispose().timeout(const Duration(seconds: 2));
        } catch (_) {}
        final vm = await VmClient.connect(uri);
        _vm = vm;
        _lastError = null;
        return vm;
      } catch (e) {
        stderr.writeln(
            'agent_wires_mcp: reattach to $uri failed ($e); rebooting');
      }
    }
    await dispose();
    return ensureReady();
  }

  Future<VmClient> _boot() async {
    _state = AppState.booting;
    _lastError = null;
    _latestProgress = null;
    try {
      final runner = FlutterRunner(
        workingDirectory: _workingDirectory!,
        deviceId: _deviceId,
        flutterArgs: _flutterArgs,
        // Stream flutter's progress messages to MCP server stderr so the
        // human (and Claude Code's MCP log viewer) can see what's happening
        // during a multi-minute cold compile. Also cache on the session
        // itself so it survives a boot failure / runner disposal — the
        // agent reads it via app_status to diagnose stuck boots.
        onProgress: (msg) {
          _latestProgress = msg;
          stderr.writeln('agent_wires_mcp: $msg');
        },
      );
      _runner = runner;
      // Large Flutter apps (firebase, syncfusion, flutter_quill, etc.) can
      // take well past 5 min on a cold compile. Be generous — the user
      // sees the wait in their progress UI anyway, and timing out
      // prematurely just bricks the session.
      await runner.start(timeout: bootTimeout);
      final vm = await VmClient.connect(runner.vmServiceUri);
      _vm = vm;
      _state = AppState.ready;
      return vm;
    } catch (e) {
      _lastError = e.toString();
      _state = AppState.exited;
      try {
        await _runner?.stop();
      } catch (_) {}
      _runner = null;
      _vm = null;
      rethrow;
    }
  }

  /// Triggers a hot reload — re-injects changed sources, preserves app state
  /// and current route. Returns the result from the underlying mechanism:
  /// `{success: bool, code?: int, message?: String}` (the exact shape
  /// depends on lazy vs attached mode).
  ///
  /// Lazy mode delegates to [FlutterRunner.hotReload] which speaks
  /// `flutter run --machine` and performs a full Flutter hot reload
  /// (sources + reassemble). Attached mode falls back to VM service
  /// `reloadSources` — sources swap but no Flutter widget-tree reassemble,
  /// so visible changes may not appear until the next rebuild.
  Future<Map<String, dynamic>> hotReload() async {
    if (_state != AppState.ready) {
      throw StateError('AppSession is not ready (state=${_state.name})');
    }
    final runner = _runner;
    if (runner != null) {
      final res = await runner.hotReload();
      return {
        'success': res['code'] == 0,
        'mode': 'flutter_machine',
        ...res,
      };
    }
    final vm = _vm;
    if (vm == null) {
      throw StateError('no VmClient attached');
    }
    final res = await vm.reloadSources();
    return {
      'mode': 'vm_service',
      'note': 'attached mode reloads sources only; widget tree may not '
          'rebuild until the next frame',
      ...res,
    };
  }

  /// Triggers a hot restart — tears down the isolate and re-runs `main()`.
  /// **State is lost**, including any login session and current route.
  /// Only supported in lazy mode (where we own the flutter process). In
  /// attached mode, throws — the caller owns the flutter subprocess and
  /// must restart it externally.
  Future<Map<String, dynamic>> hotRestart() async {
    if (_state != AppState.ready) {
      throw StateError('AppSession is not ready (state=${_state.name})');
    }
    final runner = _runner;
    if (runner == null) {
      throw StateError(
        'hot_restart requires lazy mode — attached sessions cannot restart '
        'the flutter process they did not start',
      );
    }
    final res = await runner.hotRestart();
    return {
      'success': res['code'] == 0,
      'mode': 'flutter_machine',
      ...res,
    };
  }

  Future<void> dispose() async {
    // The VM-service may already be dead — `_service.dispose()` can hang on a
    // half-open socket. Bound it so stop_app always tears down the OS process
    // (the real recovery) instead of wedging on a corpse connection (#1).
    try {
      await _vm?.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await _runner?.stop();
    } catch (_) {}
    _vm = null;
    _runner = null;
    _state = AppState.exited;
  }
}
