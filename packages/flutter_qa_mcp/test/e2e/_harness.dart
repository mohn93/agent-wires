import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Boots a Flutter app via `flutter run --machine`, parses the JSON stream
/// for the VM service URI, and exposes it for an MCP client to attach.
///
/// `flutter run` (not `flutter test`) is required because `flutter_test`'s
/// fake-async zone stops driving the widget tree's frame loop after the test
/// body's first awaited gap — `RenderObject.attached` goes false and bounds
/// disappear, so the probe sees an empty tree.
///
/// Pass the device via `FLUTTER_QA_E2E_DEVICE`, or omit to let `flutter` pick.
class FlutterTestHarness {
  late Process flutter;
  late Uri vmServiceUri;

  Future<void> start({
    required String workingDirectory,
    String? deviceId,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final device = deviceId ?? Platform.environment['FLUTTER_QA_E2E_DEVICE'];
    final args = <String>[
      'run',
      '--machine',
      if (device != null) ...['-d', device],
    ];
    flutter = await Process.start('flutter', args, workingDirectory: workingDirectory);

    final completer = Completer<Uri>();
    flutter.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final uri = _extractWsUri(line);
      if (uri != null && !completer.isCompleted) {
        completer.complete(uri);
      }
    });
    vmServiceUri = await completer.future.timeout(timeout);
  }

  Future<void> stop() async {
    flutter.kill();
    await flutter.exitCode;
  }
}

/// `flutter run --machine` emits newline-delimited events wrapped in `[...]`,
/// each carrying a `params` object. Recognised shapes:
///   `{"event":"app.debugPort","params":{"wsUri":"ws://..."}}`
///   `{"event":"app.started","params":{...}}` (no URI)
///   `{"event":"test.startedProcess","params":{"vmServiceUri":"..."}}` (test mode)
Uri? _extractWsUri(String line) {
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
