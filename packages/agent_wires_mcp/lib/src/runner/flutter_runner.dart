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
    this.onProgress,
  });

  final String workingDirectory;
  final String? deviceId;
  final List<String> flutterArgs;
  final FlutterRunMode mode;

  /// Called when `flutter run --machine` emits an `app.progress` event or a
  /// `daemon.logMessage` worth surfacing (Xcode build steps, Pod install,
  /// dart compile progress). Lets the caller stream these to its UI / logs
  /// so a long cold boot is visible instead of a 10-minute black box.
  final void Function(String message)? onProgress;

  Process? _process;
  Uri? _vmServiceUri;
  String? _appId;
  String? _latestProgress;
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

  /// The latest progress / status message from `flutter run --machine`, or
  /// null if none has been seen. Useful for diagnosing a slow boot.
  String? get latestProgress => _latestProgress;

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
      // app.progress / daemon.logMessage carry the Xcode / Pod / compile
      // status. Surface them so a slow cold boot doesn't look like a hang.
      final progress = extractProgressMessage(event, p);
      if (progress != null) {
        _latestProgress = progress;
        onProgress?.call(progress);
      }
      // Treat app.stop with an error payload, or any error-level daemon log,
      // as a hard launch failure. Without this we sit waiting for a VM
      // service URI that will never arrive (no device, build failed, etc.).
      final failure = extractLaunchFailure(event, p);
      if (failure != null && !vmReady.isCompleted) {
        vmReady.completeError(StateError('flutter launch failed: $failure'));
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

/// Returns a human-readable progress string for events that report what
/// flutter is currently doing during boot: app.progress (Xcode build steps,
/// Pod install) and informational daemon.logMessage entries.
///
/// Visible for testing — file-private helpers can't be unit-tested without
/// spawning a real flutter process.
String? extractProgressMessage(dynamic event, Map<String, dynamic> params) {
  if (event == 'app.progress') {
    final message = params['message'];
    if (message is String && message.isNotEmpty) return message;
  }
  if (event == 'daemon.logMessage') {
    final level = params['level'];
    final message = params['message'];
    if (message is String && message.isNotEmpty && level != 'error') {
      return message.length > 200 ? '${message.substring(0, 197)}...' : message;
    }
  }
  return null;
}

/// Returns an error string when the flutter launch has hard-failed and we
/// should stop waiting for the VM service URI. Triggered by app.stop with
/// an error payload (build/launch failed, app exited before reporting URI)
/// or any error-level daemon log message.
///
/// Visible for testing.
String? extractLaunchFailure(dynamic event, Map<String, dynamic> params) {
  if (event == 'app.stop') {
    final error = params['error'];
    if (error is String && error.isNotEmpty) return error;
  }
  if (event == 'daemon.logMessage' && params['level'] == 'error') {
    final message = params['message'];
    if (message is String && message.isNotEmpty) return message;
  }
  return null;
}

