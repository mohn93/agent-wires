import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/rendering.dart';
import '../actions/gesture_synth.dart';

class SwipeExtension {
  static const String name = 'ext.qa.swipe';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final fromX = double.tryParse(params['from_x'] ?? '');
    final fromY = double.tryParse(params['from_y'] ?? '');
    final toX = double.tryParse(params['to_x'] ?? '');
    final toY = double.tryParse(params['to_y'] ?? '');
    if (fromX == null || fromY == null || toX == null || toY == null) {
      return _ok({'success': false, 'error': 'from_x, from_y, to_x, to_y required'});
    }
    final ms = int.tryParse(params['duration_ms'] ?? '300') ?? 300;
    try {
      await GestureSynth.swipe(
        Offset(fromX, fromY),
        Offset(toX, toY),
        duration: Duration(milliseconds: ms),
      );
      return _ok({'success': true});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
