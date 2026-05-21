import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'raw_node.dart';

class ElementTreeWalker {
  /// Walks the live Element tree depth-first and returns one [RawNode] per
  /// Element with its widgetType, depth, sibling index, optional visible text,
  /// optional bounds (when laid out), and optional `creation_location`
  /// (`file:line:column`) when `--track-widget-creation` is enabled.
  static List<RawNode> walkFromRoot() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return const [];

    // Phase 1: one inspector group for all elements. `toId` registers each
    // element with the group; this is O(N) and cheap.
    //
    // Phase 2: a single `getDetailsSubtree` call returns the JSON for the
    // whole subtree, including `creationLocation` per node. Walk that JSON
    // once to build an `id -> location` map.
    //
    // Phase 3: walk the element tree, look up each element's id, then its
    // location. Three O(N) passes total (was O(N²) — one getDetailsSubtree
    // per element).
    const group = '_qa_probe_walk';
    final inspector = WidgetInspectorService.instance;
    final elementById = <String, Element>{};
    final out = <RawNode>[];

    try {
      String? rootId;
      void register(Element e) {
        // ignore: invalid_use_of_protected_member - WidgetInspectorService.toId is protected but has no public equivalent
        final id = inspector.toId(e, group);
        if (id != null) elementById[id] = e;
        e.visitChildren(register);
      }
      register(root);
      // ignore: invalid_use_of_protected_member - WidgetInspectorService.toId is protected but has no public equivalent
      rootId = inspector.toId(root, group);

      final locById = <String, String>{};
      if (rootId != null) {
        try {
          // Default subtreeDepth is 2 — far too shallow. 1 << 30 effectively
          // disables the limit; the inspector walks the whole element tree
          // once and we resolve every node's creationLocation from the result.
          final json = inspector.getDetailsSubtree(
            rootId,
            group,
            subtreeDepth: 1 << 30,
          );
          final tree = jsonDecode(json);
          if (tree is Map<String, dynamic>) {
            _collectLocations(tree, locById);
          }
        } catch (_) {
          // If the inspector returns nothing or fails, we just emit empty
          // creation locations rather than failing the whole snapshot.
        }
      }

      void visit(Element e, int depth, int siblingIndex) {
        // ignore: invalid_use_of_protected_member - WidgetInspectorService.toId is protected but has no public equivalent
        final id = inspector.toId(e, group);
        out.add(RawNode(
          element: e,
          widgetType: e.widget.runtimeType.toString(),
          depth: depth,
          siblingIndex: siblingIndex,
          visibleText: _extractText(e.widget),
          bounds: _extractBounds(e),
          creationLocation: id == null ? null : locById[id],
        ));
        var idx = 0;
        e.visitChildren((child) {
          visit(child, depth + 1, idx++);
        });
      }
      visit(root, 0, 0);
    } finally {
      // ignore: invalid_use_of_protected_member - WidgetInspectorService.disposeGroup is protected but has no public equivalent
      inspector.disposeGroup(group);
    }
    return out;
  }

  /// Walks the inspector's JSON tree and accumulates `valueId -> location`
  /// (`file:line:column`) for every node carrying a `creationLocation`.
  static void _collectLocations(
      Map<String, dynamic> node, Map<String, String> out) {
    final valueId = node['valueId'] as String?;
    final loc = node['creationLocation'] as Map<String, dynamic>?;
    if (valueId != null && loc != null) {
      final file = (loc['file'] as String).replaceFirst('file://', '');
      out[valueId] = '$file:${loc['line']}:${loc['column']}';
    }
    final children = node['children'] as List?;
    if (children != null) {
      for (final c in children) {
        if (c is Map<String, dynamic>) _collectLocations(c, out);
      }
    }
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
}
