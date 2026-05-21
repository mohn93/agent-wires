import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import '../tree/snapshot_builder.dart';

class WaitForElementExtension {
  static const String name = 'ext.qa.wait_for_element';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final labelQuery = params['label'];
    final roleQuery = params['role'];
    if ((labelQuery == null || labelQuery.isEmpty) &&
        (roleQuery == null || roleQuery.isEmpty)) {
      return _ok({'success': false, 'error': 'label or role required'});
    }
    final timeoutMs = int.tryParse(params['timeout_ms'] ?? '5000') ?? 5000;
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      final snap = SnapshotBuilder.build();
      for (final el in snap.elements) {
        final labelOk = labelQuery == null || labelQuery.isEmpty || el.label == labelQuery;
        final roleOk = roleQuery == null || roleQuery.isEmpty || el.role == roleQuery;
        if (labelOk && roleOk) {
          return _ok({'success': true, 'matched': true, 'element_id': el.id});
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _ok({'success': true, 'matched': false});
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
