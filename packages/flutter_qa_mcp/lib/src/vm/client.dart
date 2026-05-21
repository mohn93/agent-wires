import 'dart:convert';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

class VmClient {
  VmClient._(this._service, this._isolateId);

  final VmService _service;
  final String _isolateId;

  static Future<VmClient> connect(Uri uri) async {
    if (uri.scheme != 'ws' && uri.scheme != 'wss') {
      throw ArgumentError('VM service URI must be ws:// or wss://, got: $uri');
    }
    final service = await vmServiceConnectUri(uri.toString());
    final vm = await service.getVM();
    final isolateRef = vm.isolates?.firstWhere(
      (i) => i.id != null,
      orElse: () => throw StateError('no isolates in VM'),
    );
    return VmClient._(service, isolateRef!.id!);
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

  Future<void> dispose() async {
    await _service.dispose();
  }
}
