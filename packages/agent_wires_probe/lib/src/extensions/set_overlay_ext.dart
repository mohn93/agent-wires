import 'dart:convert';
import 'dart:developer' as developer;
import '../overlay/action_overlay_controller.dart';

class SetOverlayExtension {
  static const String name = 'ext.qa.set_overlay';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final raw = params['enabled'];
    if (raw == null) {
      return _ok({'success': false, 'error': 'enabled required'});
    }
    final enabled = raw == 'true';
    ActionOverlayController.instance.setEnabled(enabled);
    return _ok({'success': true, 'enabled': enabled});
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
