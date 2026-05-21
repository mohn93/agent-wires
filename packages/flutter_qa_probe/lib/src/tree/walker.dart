import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'raw_node.dart';

class ElementTreeWalker {
  static List<RawNode> walkFromRoot() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return const [];
    final out = <RawNode>[];
    _visit(root, depth: 0, siblingIndex: 0, out: out);
    return out;
  }

  static void _visit(Element e,
      {required int depth, required int siblingIndex, required List<RawNode> out}) {
    out.add(RawNode(
      element: e,
      widgetType: e.widget.runtimeType.toString(),
      depth: depth,
      siblingIndex: siblingIndex,
      visibleText: _extractText(e.widget),
      bounds: _extractBounds(e),
      creationLocation: _extractCreationLocation(e),
    ));
    var idx = 0;
    e.visitChildren((child) {
      _visit(child, depth: depth + 1, siblingIndex: idx++, out: out);
    });
  }

  static String? _extractText(Widget w) {
    if (w is Text) return w.data;
    if (w is RichText) return w.text.toPlainText();
    return null;
  }

  static Rect? _extractBounds(Element e) {
    final ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize && ro.attached) {
      final origin = ro.localToGlobal(Offset.zero);
      return origin & ro.size;
    }
    return null;
  }

  static String? _extractCreationLocation(Element e) {
    // WidgetInspectorService.getDetailsSubtree provides creationLocation when
    // --track-widget-creation is enabled (the default for flutter test and debug).
    const group = '_qa_probe_cl';
    final inspector = WidgetInspectorService.instance;
    final nodeId = inspector.toId(e, group);
    if (nodeId == null) return null;
    try {
      final json = inspector.getDetailsSubtree(nodeId, group);
      final map = jsonDecode(json) as Map<String, dynamic>;
      final loc = map['creationLocation'] as Map<String, dynamic>?;
      if (loc == null) return null;
      final file = (loc['file'] as String).replaceFirst('file://', '');
      return '$file:${loc['line']}:${loc['column']}';
    } catch (_) {
      return null;
    } finally {
      inspector.disposeGroup(group);
    }
  }
}
