import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Drives `flutter run --machine` as a subprocess, parses its newline-delimited
/// JSON event stream for the VM service URI, captures the appId, and exposes
/// hot-reload / hot-restart commands over the same stdin pipe.
///
/// Also handles `flutter test --machine` (used by integration tests) — both
/// formats are recognised by [_extractVmServiceUri].
class FlutterRunner {
  FlutterRunner({
    required this.workingDirectory,
    this.deviceId,
    this.flutterArgs = const <String>[],
    this.mode = FlutterRunMode.run,
  });

  final String workingDirectory;
  final String? deviceId;
  final List<String> flutterArgs;
  final FlutterRunMode mode;

  Process? _process;
  Uri? _vmServiceUri;
  String? _appId;
  int _nextRequestId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pendingResponses = {};

  /// The VM service URI reported by `flutter`. Populated after [start] completes.
  Uri get vmServiceUri => _vmServiceUri ??
      (throw StateError('FlutterRunner.start() has not completed'));

  /// Non-throwing variant of [vmServiceUri] for callers that legitimately want
  /// to peek before [start] has resolved (e.g. status tools).
  Uri? get vmServiceUriOrNull => _vmServiceUri;

  /// The Flutter app id reported by the `app.started` event. Required for
  /// `app.restart` (hot reload / hot restart) calls.
  String? get appId => _appId;

  /// Spawns `flutter run` / `flutter test` and blocks until the VM service URI
  /// is reported (or [timeout] elapses).
  Future<void> start({Duration timeout = const Duration(minutes: 5)}) async {
    final args = <String>[
      switch (mode) {
        FlutterRunMode.run => 'run',
        FlutterRunMode.test => 'test',
      },
      ...flutterArgs,
      '--machine',
      if (deviceId != null) ...['-d', deviceId!],
    ];
    final proc = await Process.start(
      'flutter',
      args,
      workingDirectory: workingDirectory,
    );
    _process = proc;

    final vmReady = Completer<Uri>();
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _onStdoutLine(line, vmReady));
    // Surface flutter's stderr so the caller can debug build failures.
    proc.stderr.transform(utf8.decoder).listen(stderr.write);

    try {
      _vmServiceUri = await vmReady.future.timeout(timeout);
    } on TimeoutException {
      await stop();
      rethrow;
    }
  }

  /// Triggers a hot reload (state-preserving source reinjection). Requires
  /// [mode] = `FlutterRunMode.run` and a captured [appId]. Returns the parsed
  /// response from `flutter run --machine`: `{code: int, message?: String}`.
  /// `code: 0` means success; non-zero means the reload was rejected (compile
  /// error, hot-reload-incompatible change, etc.).
  Future<Map<String, dynamic>> hotReload({
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _restart(fullRestart: false, timeout: timeout);

  /// Triggers a hot restart (tears down the isolate and re-runs `main()`).
  /// State is lost. Slower than hot reload but always works as long as the
  /// app compiles. Same response shape as [hotReload].
  Future<Map<String, dynamic>> hotRestart({
    Duration timeout = const Duration(seconds: 60),
  }) =>
      _restart(fullRestart: true, timeout: timeout);

  Future<Map<String, dynamic>> _restart({
    required bool fullRestart,
    required Duration timeout,
  }) async {
    final proc = _process;
    if (proc == null) {
      throw StateError('FlutterRunner.start() has not been called');
    }
    final id = _appId;
    if (id == null) {
      throw StateError(
        'no appId captured — flutter never emitted `app.started`',
      );
    }
    final reqId = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingResponses[reqId] = completer;
    final cmd = jsonEncode([
      {
        'id': reqId,
        'method': 'app.restart',
        'params': {
          'appId': id,
          'fullRestart': fullRestart,
          'pause': false,
        },
      }
    ]);
    proc.stdin.writeln(cmd);
    await proc.stdin.flush();
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pendingResponses.remove(reqId);
      rethrow;
    }
  }

  void _onStdoutLine(String line, Completer<Uri> vmReady) {
    final parsed = _safeDecode(line);
    if (parsed == null) return;
    final messages = parsed is List ? parsed : [parsed];
    for (final m in messages) {
      if (m is! Map) continue;
      _dispatch(m.cast<String, dynamic>(), vmReady);
    }
  }

  void _dispatch(Map<String, dynamic> msg, Completer<Uri> vmReady) {
    final params = msg['params'];
    if (params is Map) {
      final p = params.cast<String, dynamic>();
      final event = msg['event'];
      // app.started carries the appId we need for subsequent restart calls.
      if (event == 'app.started') {
        final appId = p['appId'];
        if (appId is String) _appId = appId;
      }
      // VM service URI can appear on debugPort, started, or test.startedProcess.
      final uri = _extractVmServiceUriFromParams(p);
      if (uri != null && !vmReady.isCompleted) vmReady.complete(uri);
    }

    final id = msg['id'];
    if (id is int) {
      final pending = _pendingResponses.remove(id);
      if (pending != null && !pending.isCompleted) {
        final result = msg['result'];
        if (result is Map) {
          pending.complete(result.cast<String, dynamic>());
        } else if (result != null) {
          pending.complete({'result': result});
        } else if (msg['error'] != null) {
          pending.completeError(StateError('flutter error: ${msg['error']}'));
        } else {
          pending.complete(const {});
        }
      }
    }
  }

  Future<void> stop() async {
    final proc = _process;
    if (proc == null) return;
    proc.kill();
    await proc.exitCode;
    _process = null;
    _appId = null;
    for (final c in _pendingResponses.values) {
      if (!c.isCompleted) c.completeError(StateError('FlutterRunner stopped'));
    }
    _pendingResponses.clear();
  }
}

enum FlutterRunMode { run, test }

dynamic _safeDecode(String line) {
  try {
    return jsonDecode(line);
  } catch (_) {
    return null;
  }
}

/// Recognises the VM service URI in the various shapes `flutter run --machine`
/// and `flutter test --machine` emit it.
Uri? _extractVmServiceUriFromParams(Map<String, dynamic> params) {
  final candidate =
      params['wsUri'] ?? params['vmServiceUri'] ?? params['observatoryUri'];
  if (candidate is String) return Uri.parse(candidate);
  return null;
}

