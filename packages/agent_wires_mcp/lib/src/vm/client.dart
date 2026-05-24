import 'dart:async';
import 'dart:convert';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

class VmClient {
  VmClient._(this._service, this._isolateId);

  /// Named constructor for test subclasses. Initialises fields with no-op
  /// values; subclasses should override [callExtension].
  VmClient.test()
      : _service = VmService(const Stream.empty(), (_) {}),
        _isolateId = '';

  final VmService _service;
  final String _isolateId;

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

  Future<Map<String, dynamic>> callExtension(
    String name, [
    Map<String, dynamic>? args,
  ]) async {
    final stringArgs = <String, String>{};
    args?.forEach((k, v) => stringArgs[k] = v is String ? v : jsonEncode(v));
    final response = await _service.callServiceExtension(
      name,
      isolateId: _isolateId,
      args: stringArgs,
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
