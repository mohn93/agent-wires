import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import '../tree/element_record.dart';
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
    final wantLabel = labelQuery != null && labelQuery.isNotEmpty;
    final wantRole = roleQuery != null && roleQuery.isNotEmpty;
    final mode = (params['match'] ?? 'exact').toLowerCase();
    if (mode != 'exact' && mode != 'substring') {
      return _ok({'success': false, 'error': 'match must be exact|substring'});
    }
    // Labels are inferred from descendant text ("Domains · Manage your
    // domains"), so callers rarely know the full string. `match: substring`
    // opts into a case-insensitive, word-boundary match; it stays opt-in so
    // existing exact waits keep gating on the widget they named, and the
    // boundary keeps "OK" from matching "Book now".
    final RegExp? needle = wantLabel && mode == 'substring'
        ? RegExp('(^|\\W)${RegExp.escape(labelQuery)}(\\W|\$)',
            caseSensitive: false)
        : null;
    while (DateTime.now().isBefore(deadline)) {
      final snap = SnapshotBuilder.build();
      ElementRecord? exact;
      ElementRecord? partial;
      for (final el in snap.elements) {
        if (wantRole && el.role != roleQuery) continue;
        if (!wantLabel) {
          exact = el;
          break;
        }
        final label = el.label;
        if (label == null) continue;
        if (label == labelQuery) {
          exact = el;
          break;
        }
        if (needle != null && partial == null && needle.hasMatch(label)) {
          partial = el;
        }
      }
      final hit = exact ?? partial;
      if (hit != null) {
        return _ok({
          'success': true,
          'matched': true,
          'element_id': hit.id,
          if (hit.label != null) 'label': hit.label,
          'match': !wantLabel
              ? 'role'
              : exact != null
                  ? 'exact'
                  : 'substring',
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _ok({'success': true, 'matched': false});
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
