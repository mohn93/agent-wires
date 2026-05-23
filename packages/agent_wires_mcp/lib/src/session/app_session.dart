import 'dart:async';

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

  /// Returns the connected [VmClient]. If the session is lazy and hasn't been
  /// booted yet, this kicks off `flutter run --machine`, waits for the VM
  /// service URI, and attaches. Concurrent callers share one boot future.
  Future<VmClient> ensureReady() async {
    if (_state == AppState.ready && _vm != null) return _vm!;
    if (_state == AppState.exited) {
      throw StateError(
        'AppSession is exited${_lastError == null ? '' : ': $_lastError'}',
      );
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
      );
      _runner = runner;
      await runner.start();
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
