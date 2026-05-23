import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/rendering.dart';
import '../actions/gesture_synth.dart';
import '../resolver/element_resolver.dart';

class TapExtension {
  static const String name = 'ext.qa.tap';

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
    final ro = element.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) {
      return _ok({'success': false, 'error': 'element has no render box'});
    }
    final center = ro.localToGlobal(ro.size.center(Offset.zero));
    try {
      await GestureSynth.tapAt(center);
      return _ok({'success': true, 'at': {'x': center.dx, 'y': center.dy}});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
