import 'package:flutter/widgets.dart';

class RawNode {
  RawNode({
    required this.element,
    required this.widgetType,
    required this.depth,
    required this.siblingIndex,
    this.visibleText,
    this.bounds,
    this.creationLocation,
  });

  final Element element;
  final String widgetType;
  final int depth;
  final int siblingIndex;
  final String? visibleText;
  final Rect? bounds;
  final String? creationLocation; // "file:line:column"
}
