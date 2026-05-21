import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ScreenshotExtension {
  static const String name = 'ext.qa.screenshot';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final boundary = _findRootRepaintBoundary();
      if (boundary == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          jsonEncode({'error': 'no RepaintBoundary found'}),
        );
      }
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          jsonEncode({'error': 'failed to encode PNG'}),
        );
      }
      final b64 = base64Encode(bytes.buffer.asUint8List());
      return developer.ServiceExtensionResponse.result(jsonEncode({
        'format': 'png',
        'width': image.width,
        'height': image.height,
        'data_base64': b64,
      }));
    } catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': e.toString()}),
      );
    }
  }

  static RenderRepaintBoundary? _findRootRepaintBoundary() {
    RenderRepaintBoundary? found;
    void walk(RenderObject ro) {
      if (found != null) return;
      if (ro is RenderRepaintBoundary) {
        found = ro;
        return;
      }
      ro.visitChildren(walk);
    }
    final root = WidgetsBinding.instance.rootElement?.renderObject;
    if (root != null) walk(root);
    return found;
  }
}
