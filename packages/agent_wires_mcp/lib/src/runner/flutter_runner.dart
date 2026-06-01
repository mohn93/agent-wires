import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'process_tree.dart';

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
    this.executable = 'flutter',
  });

  final String workingDirectory;
  final String? deviceId;
  final List<String> flutterArgs;
  final FlutterRunMode mode;

  /// The command to spawn. Always `flutter` in production; a test seam so the
  /// boot path can be exercised against a process that exits deterministically.
  final String executable;

  /// Called when `flutter run --machine` emits an `app.progress` event or a
  /// `daemon.logMessage` worth surfacing (Xcode build steps, Pod install,
  /// dart compile progress). Lets the caller stream these to its UI / logs
  /// so a long cold boot is visible instead of a 10-minute black box.
  final void Function(String message)? onProgress;

  Process? _process;
  Uri? _vmServiceUri;
  String? _appId;
  String? _latestProgress;
  final StringBuffer _stderrTail = StringBuffer();
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
      executable,
      args,
      workingDirectory: workingDirectory,
    );
    _process = proc;

    final vmReady = Completer<Uri>();
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _onStdoutLine(line, vmReady));
    // Surface flutter's stderr so the caller can debug build failures, and
    // keep a tail of it to attach to a premature-exit error below.
    proc.stderr.transform(utf8.decoder).listen((chunk) {
      stderr.write(chunk);
      _appendStderrTail(chunk);
    });

    // Fail fast if flutter exits before reporting a VM service URI. Without
    // this, a `flutter run` that dies during the build (codesign failure, no
    // matching device, or `flutter` resolving to the wrong SDK — e.g. an
    // fvm-managed Flutter not on the spawned PATH) leaves the boot hanging on
    // the full timeout while app_status shows a frozen "Running Xcode
    // build..." and no flutter/xcodebuild process is even alive.
    unawaited(proc.exitCode.then((code) {
      if (vmReady.isCompleted) return;
      final tail = _stderrTail.toString().trim();
      vmReady.completeError(StateError(
        'flutter exited (code $code) before reporting a VM service URI — the '
        'boot failed rather than completing. '
        '${_latestProgress != null ? 'Last progress: "$_latestProgress". ' : ''}'
        'Common causes: a build/codesign failure, no matching device, or '
        '`flutter` resolving to the wrong SDK (e.g. an fvm-managed Flutter not '
        "on the MCP server's PATH — try an absolute path or `fvm dart pub "
        'global run`).'
        '${tail.isNotEmpty ? '\n--- flutter stderr (tail) ---\n$tail' : ''}',
      ));
    }));

    try {
      _vmServiceUri = await vmReady.future.timeout(timeout);
    } on TimeoutException {
      await stop();
      rethrow;
    }
  }

  /// Keeps a bounded tail of flutter's stderr so a premature-exit error can
  /// quote the actual failure instead of leaving the agent blind.
  void _appendStderrTail(String chunk) {
    _stderrTail.write(chunk);
    const cap = 4000;
    if (_stderrTail.length > cap) {
      final s = _stderrTail.toString();
      _stderrTail
        ..clear()
        ..write(s.substring(s.length - cap));
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
    var res = await sendRestart(fullRestart: fullRestart, timeout: timeout);
    if (!isDevFsSyncFailure(res)) return res;
    // DevFS sync hiccups are often transient (a late device, a half-applied
    // diff). Retry the same operation once to re-establish the DevFS before
    // giving up (#5).
    res = await sendRestart(fullRestart: fullRestart, timeout: timeout);
    if (!isDevFsSyncFailure(res)) return res;
    // Still wedged after a retry — DevFS won't recover via reload/restart.
    // Surface that explicitly with the recovery path rather than a bare fail.
    return withDevFsRecoveryHint(res);
  }

  /// Sends a single `app.restart` to `flutter run --machine` and awaits its
  /// response: `{code: int, message?: String}`. Seam for tests and for the
  /// DevFS retry wrapper in [_restart].
  @visibleForTesting
  Future<Map<String, dynamic>> sendRestart({
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
    // Reap the whole tree, not just the flutter PID: `flutter run` forks a DDS
    // (`dart development-service`), and on a physical device a devicectl/script
    // wrapper plus an `iproxy` USB tunnel. Killing only `proc` orphans those to
    // launchd, where they keep contending for the device + VM-service and
    // destabilise the next session (#2).
    await ProcessTree.reap(proc.pid);
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

/// True when an `app.restart` response is the flutter "DevFS synchronization
/// failed" error — the wedge where hot reload/restart can no longer push code.
/// Visible for testing.
bool isDevFsSyncFailure(Map<String, dynamic> result) {
  if (result['code'] == 0) return false;
  final message = (result['message'] ?? '').toString().toLowerCase();
  return message.contains('devfs synchronization');
}

/// Annotates an unrecoverable DevFS failure with the actual recovery path, so
/// the agent gets an actionable next step instead of a bare `success:false`.
/// Visible for testing.
Map<String, dynamic> withDevFsRecoveryHint(Map<String, dynamic> result) => {
      ...result,
      'recoverable': false,
      'hint': 'DevFS is wedged and a retry did not recover. Hot reload/restart '
          'cannot fix this — run stop_app then boot_app to rebuild.',
    };

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

