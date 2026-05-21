import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/widgets.dart';

class PressBackExtension {
  static const String name = 'ext.qa.press_back';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final root = WidgetsBinding.instance.rootElement;
      if (root == null) {
        return _ok({'success': false, 'error': 'no root element'});
      }
      NavigatorState? nav;
      void visit(Element e) {
        if (nav != null) return;
        if (e is StatefulElement && e.state is NavigatorState) {
          nav = e.state as NavigatorState;
          return;
        }
        e.visitChildren(visit);
      }
      visit(root);
      if (nav == null) {
        return _ok({'success': false, 'error': 'no Navigator found'});
      }
      final popped = await nav!.maybePop();
      return _ok({'success': popped});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
