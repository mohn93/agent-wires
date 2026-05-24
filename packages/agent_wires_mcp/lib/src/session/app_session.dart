import 'dart:async';
import 'dart:io';

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
  })  : _workingDirectory = workingDirectory,
        _deviceId = deviceId,
        _flutterArgs = flutterArgs,
        _attached = false;

  AppSession.attached(VmClient vm)
      : _workingDirectory = null,
        _deviceId = null,
        _flutterArgs = const <String>[],
        _attached = true,
        _vm = vm,
        _state = AppState.ready;

  final String? _workingDirectory;
  final String? _deviceId;
  final List<String> _flutterArgs;
  final bool _attached;

  FlutterRunner? _runner;
  VmClient? _vm;
  AppState _state = AppState.idle;
  String? _lastError;
  Future<VmClient>? _bootFuture;

  AppState get state => _state;
  String? get lastError => _lastError;
  String? get deviceId => _deviceId;
  Uri? get vmServiceUri =>
      _state == AppState.ready ? _runner?.vmServiceUriOrNull : null;

  /// The latest progress message from `flutter run --machine` (Xcode build
  /// step, Pod install line, dart compile progress). Useful for diagnosing
  /// a slow or stuck boot.
  String? get latestProgress => _runner?.latestProgress;

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
    if (_state == AppState.ready && _vm != null) return _vm!;
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

  Future<VmClient> _boot() async {
    _state = AppState.booting;
    _lastError = null;
    try {
      final runner = FlutterRunner(
        workingDirectory: _workingDirectory!,
        deviceId: _deviceId,
        flutterArgs: _flutterArgs,
        // Stream flutter's progress messages to MCP server stderr so the
        // human (and Claude Code's MCP log viewer) can see what's happening
        // during a multi-minute cold compile.
        onProgress: (msg) => stderr.writeln('agent_wires_mcp: $msg'),
      );
      _runner = runner;
      // Large Flutter apps (firebase, syncfusion, flutter_quill, etc.) can
      // take well past 5 min on a cold compile. Be generous — the user
      // sees the wait in their progress UI anyway, and timing out
      // prematurely just bricks the session.
      await runner.start(timeout: const Duration(minutes: 10));
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
    try {
      await _vm?.dispose();
    } catch (_) {}
    try {
      await _runner?.stop();
    } catch (_) {}
    _vm = null;
    _runner = null;
    _state = AppState.exited;
  }
}
