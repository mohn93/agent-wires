import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Drives `flutter run --machine` as a subprocess, parses its newline-delimited
/// JSON event stream for the VM service URI, and exposes that URI for an MCP
/// server to attach to.
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

  /// The VM service URI reported by `flutter`. Populated after [start] completes.
  Uri get vmServiceUri => _vmServiceUri ??
      (throw StateError('FlutterRunner.start() has not completed'));

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

    final completer = Completer<Uri>();
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final uri = _extractVmServiceUri(line);
      if (uri != null && !completer.isCompleted) {
        completer.complete(uri);
      }
    });
    // Surface flutter's stderr so the caller can debug build failures.
    proc.stderr
        .transform(utf8.decoder)
        .listen(stderr.write);

    try {
      _vmServiceUri = await completer.future.timeout(timeout);
    } on TimeoutException {
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    final proc = _process;
    if (proc == null) return;
    proc.kill();
    await proc.exitCode;
    _process = null;
  }
}

enum FlutterRunMode { run, test }

/// `flutter run --machine` emits one JSON event per line, wrapped in `[...]`,
/// each carrying a `params` object. Recognised shapes:
///   `{"event":"app.debugPort","params":{"wsUri":"ws://..."}}`
///   `{"event":"test.startedProcess","params":{"vmServiceUri":"..."}}`
///   `{"event":"app.started","params":{...}}` (no URI here — ignored)
///   legacy `{"params":{"observatoryUri":"..."}}`
Uri? _extractVmServiceUri(String line) {
  dynamic parsed;
  try {
    parsed = jsonDecode(line);
  } catch (_) {
    return null;
  }
  if (parsed is List && parsed.isNotEmpty) parsed = parsed.first;
  if (parsed is! Map) return null;
  final params = parsed['params'];
  if (params is! Map) return null;
  final candidate = params['wsUri'] ??
      params['vmServiceUri'] ??
      params['observatoryUri'];
  if (candidate is String) return Uri.parse(candidate);
  return null;
}
