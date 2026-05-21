import 'package:flutter/widgets.dart';
import '../tree/classifier.dart';
import '../tree/walker.dart';

class ElementResolver {
  static Element? resolve(String elementId) {
    if (!elementId.startsWith('e_')) return null;
    final idx = int.tryParse(elementId.substring(2));
    if (idx == null || idx < 0) return null;

    final raw = ElementTreeWalker.walkFromRoot();
    var cursor = 0;
    for (final node in raw) {
      final cls = Classifier.classify(node.element.widget);
      if (cls != Classification.promote) continue;
      if (node.bounds == null) continue;
      if (cursor == idx) return node.element;
      cursor++;
    }
    return null;
  }
}
