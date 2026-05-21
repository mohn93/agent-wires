import 'dart:convert';
import 'dart:developer' as developer;
import '../actions/text_input_driver.dart';
import '../resolver/element_resolver.dart';

class ClearTextExtension {
  static const String name = 'ext.qa.clear_text';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final id = params['element_id'];
    if (id == null || id.isEmpty) {
      return _ok({'success': false, 'error': 'element_id required'});
    }
    final element = ElementResolver.resolve(id);
    if (element == null) {
      return _ok({'success': false, 'error': 'element not found: $id'});
    }
    try {
      await TextInputDriver.setText(element, '');
      return _ok({'success': true});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
