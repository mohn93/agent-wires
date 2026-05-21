import 'dart:convert';
import 'package:image/image.dart';

class SomAnnotator {
  /// Annotates a base64 PNG with numbered boxes for each element with bounds.
  /// Numbering is 1-based and matches the element's position in the input list.
  /// Resolved [elements] are drawn with a red outline; [unresolved] elements
  /// continue the numbering after resolved elements and use an orange outline
  /// so viewers can distinguish them at a glance.
  static String annotate({
    required String pngBase64,
    required List<Map<String, dynamic>> elements,
    List<Map<String, dynamic>> unresolved = const [],
  }) {
    final bytes = base64Decode(pngBase64);
    final img = decodePng(bytes);
    if (img == null) return pngBase64;

    final resolvedColor = ColorRgb8(255, 80, 80);
    final unresolvedColor = ColorRgb8(255, 165, 0);

    void drawBox(Image image, Map<String, dynamic> el, int number, Color color) {
      final bounds = el['bounds'] as Map?;
      if (bounds == null) return;
      final x = (bounds['x'] as num).toInt();
      final y = (bounds['y'] as num).toInt();
      final w = (bounds['w'] as num).toInt();
      final h = (bounds['h'] as num).toInt();
      drawRect(image,
          x1: x, y1: y, x2: x + w, y2: y + h, color: color, thickness: 2);
      drawString(
        image,
        '$number',
        font: arial14,
        x: x + 2,
        y: y + 2,
        color: color,
      );
    }

    for (var i = 0; i < elements.length; i++) {
      drawBox(img, elements[i], i + 1, resolvedColor);
    }

    final offset = elements.length;
    for (var i = 0; i < unresolved.length; i++) {
      drawBox(img, unresolved[i], offset + i + 1, unresolvedColor);
    }

    return base64Encode(encodePng(img));
  }
}
