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
      creationLocation: _extractCreationLocation(e.widget),
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

  static String? _extractCreationLocation(Widget w) {
    // `Widget` has a `_location` field set by --track-widget-creation.
    // Accessed via toString of the debugFillProperties / via internal API.
    // For now, use the documented `DiagnosticableTreeMixin` route.
    // ignore: unused_local_variable
    final diag = w.toDiagnosticsNode();
    // Real implementation goes through Widget._location reflection in next task.
    return null;
  }
}
