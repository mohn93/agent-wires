import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/painting.dart';
import '../actions/scroll_driver.dart';
import '../overlay/action_overlay_controller.dart';
import '../overlay/action_overlay_installer.dart';
import '../overlay/overlay_geometry.dart';
import '../resolver/element_resolver.dart';

class ScrollExtension {
  static const String name = 'ext.qa.scroll';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final dirStr = (params['direction'] ?? '').toLowerCase();
    final direction = switch (dirStr) {
      'up' => ScrollDir.up,
      'down' => ScrollDir.down,
      'left' => ScrollDir.left,
      'right' => ScrollDir.right,
      _ => null,
    };
    if (direction == null) {
      return _ok({'success': false, 'error': 'direction must be up|down|left|right'});
    }
    final distance = double.tryParse(params['distance'] ?? '200') ?? 200;
    final id = params['element_id'];
    try {
      bool ok;
      if (id != null && id.isNotEmpty) {
        final element = ElementResolver.resolve(id);
        if (element == null) {
          return _ok({'success': false, 'error': 'element not found: $id'});
        }
        ok = await ScrollDriver.scrollIn(element, direction, distance);
      } else {
        ok = await ScrollDriver.scrollAnyVisible(direction, distance);
      }
      if (!ok) {
        return _ok({'success': false, 'error': 'no scrollable found or axis mismatch'});
      }
      final size = currentScreenSize();
      final center = Offset(size.width / 2, size.height / 2);
      final to = center +
          directionVector(direction.name) * distance.clamp(40, 200).toDouble();
      ActionOverlayController.instance.showDrag(center, to);
      ActionOverlayInstaller.ensureInstalled();
      return _ok({'success': true});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
