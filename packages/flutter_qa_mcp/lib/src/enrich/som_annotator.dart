import 'dart:convert';
import 'package:image/image.dart';

class SomAnnotator {
  /// Annotates a base64 PNG with numbered boxes for each element with bounds.
  /// Numbering is 1-based and matches the element's position in the input list.
  static String annotate({
    required String pngBase64,
    required List<Map<String, dynamic>> elements,
  }) {
    final bytes = base64Decode(pngBase64);
    final img = decodePng(bytes);
    if (img == null) return pngBase64;

    final outline = ColorRgb8(255, 80, 80);

    for (var i = 0; i < elements.length; i++) {
      final el = elements[i];
      final bounds = el['bounds'] as Map?;
      if (bounds == null) continue;
      final x = (bounds['x'] as num).toInt();
      final y = (bounds['y'] as num).toInt();
      final w = (bounds['w'] as num).toInt();
      final h = (bounds['h'] as num).toInt();
      drawRect(img,
          x1: x, y1: y, x2: x + w, y2: y + h, color: outline, thickness: 2);
      drawString(
        img,
        '${i + 1}',
        font: arial14,
        x: x + 2,
        y: y + 2,
        color: outline,
      );
    }

    return base64Encode(encodePng(img));
  }
}
