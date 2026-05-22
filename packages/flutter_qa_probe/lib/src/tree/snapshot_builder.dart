import 'package:flutter/widgets.dart';
import '../probe.dart';
import 'classifier.dart';
import 'element_record.dart';
import 'fingerprint.dart';
import 'role_inference.dart';
import 'walker.dart';

class SnapshotBuilder {
  /// Widget types that are promoted only because their handler/listener fires;
  /// they are "plumbing" inside a more specific named widget. If one of these
  /// has a named promoted descendant (a Button, ListTile, TextField, etc.),
  /// suppress the generic wrapper and let the descendant represent the target.
  static const Set<String> _genericGesture = {
    'Listener',
    'GestureDetector',
    'InkWell',
  };

  static SnapshotRecord build() {
    final raw = ElementTreeWalker.walkFromRoot();
    final elements = <ElementRecord>[];
    final unresolved = <ElementRecord>[];
    var cursor = 0;

    // Compute subtree ranges so we can ask "is node B in node A's subtree"
    // in O(1). raw is in DFS order; subtreeEnd[i] is the index of the last
    // descendant of raw[i] (or i itself if it has none).
    final n = raw.length;
    final subtreeEnd = List<int>.filled(n, 0);
    for (var i = n - 1; i >= 0; i--) {
      var j = i + 1;
      while (j < n && raw[j].depth > raw[i].depth) {
        j = subtreeEnd[j] + 1;
      }
      subtreeEnd[i] = j - 1;
    }

    // Precompute which nodes are promoted-with-bounds. We need to look
    // ahead from a generic gesture wrapper to see if any named widget
    // lives in its subtree, so a single isPromoted lookup is reused.
    final promoted = List<bool>.filled(n, false);
    for (var i = 0; i < n; i++) {
      final node = raw[i];
      if (node.bounds == null) continue;
      if (Classifier.classify(node.element.widget) == Classification.promote) {
        promoted[i] = true;
      }
    }

    // Dedup pass: two rules collapse the button → InkWell → GestureDetector
    // → Listener chain (4 entries → 1) while preserving sibling targets
    // that just happen to share a DFS ancestor (e.g. a device_preview
    // ListTile that wraps the entire app).
    //
    // 1. Generic-with-named-descendant: a Listener/GestureDetector/InkWell
    //    that has a named promoted descendant in its subtree is plumbing
    //    for that descendant. Catches Scaffold-level Listeners covering
    //    the viewport when buttons live inside.
    //
    // 2. Same-bounds-as-ancestor: a promoted descendant whose bounds are
    //    contained within and roughly the same size as a kept ancestor's
    //    bounds is plumbing for that ancestor (the InkWell + GestureDetector
    //    + Listener stack inside a button all share the button's rect).
    //    Descendants at substantially different bounds are siblings of the
    //    ancestor in terms of UI and stay independent.
    //
    // keptStack holds (subtreeEnd, bounds) for currently-active ancestors;
    // we pop entries whose subtree we've exited.
    final keptStack = <_Kept>[];

    for (var i = 0; i < n; i++) {
      while (keptStack.isNotEmpty && keptStack.last.subtreeEnd < i) {
        keptStack.removeLast();
      }
      if (!promoted[i]) continue;

      final node = raw[i];

      // Rule 2: same-bounds-as-kept-ancestor → drop.
      var subsumed = false;
      for (final k in keptStack) {
        if (_containedAndSimilar(node.bounds!, k.bounds)) {
          subsumed = true;
          break;
        }
      }
      if (subsumed) continue;

      // Rule 1: drop generic wrappers that contain a named widget.
      if (_genericGesture.contains(node.widgetType)) {
        var hasNamedDescendant = false;
        for (var j = i + 1; j <= subtreeEnd[i]; j++) {
          if (!promoted[j]) continue;
          if (!_genericGesture.contains(raw[j].widgetType)) {
            hasNamedDescendant = true;
            break;
          }
        }
        if (hasNamedDescendant) continue;
      }

      final ancestors = _ancestorTypes(node.element);
      final inferred = RoleInference.infer(node.element);
      final fp = Fingerprint.compute(
        creationLocation: node.creationLocation,
        widgetType: node.widgetType,
        ancestorTypes: ancestors,
        siblingIndex: node.siblingIndex,
        visibleText: inferred.label,
      );

      final record = ElementRecord(
        id: 'e_$cursor',
        fingerprint: fp,
        widgetType: node.widgetType,
        role: inferred.role,
        label: inferred.label,
        labelSource: inferred.labelSource.name,
        bounds: node.bounds,
        creationLocation: node.creationLocation,
        enabled: true,
      );
      if (inferred.label != null) {
        elements.add(record);
      } else {
        unresolved.add(record);
      }
      cursor++;
      keptStack.add(_Kept(subtreeEnd[i], node.bounds!));
    }

    final media = MediaQueryData.fromView(WidgetsBinding.instance.platformDispatcher.views.first);
    return SnapshotRecord(
      route: FlutterQAProbe.routeTracker.currentRoute,
      viewport: media.size,
      elements: elements,
      unresolved: unresolved,
    );
  }

  /// True when [child]'s rect sits inside [parent]'s rect (within a few
  /// pixels of slack) AND covers at least 60% of the parent's area. The
  /// gesture chain inside a button — InkWell, GestureDetector, Listener —
  /// satisfies this against the button. A sibling widget rendered in a
  /// different part of the screen does not.
  static bool _containedAndSimilar(Rect child, Rect parent) {
    const eps = 4.0;
    if (child.left < parent.left - eps) return false;
    if (child.top < parent.top - eps) return false;
    if (child.right > parent.right + eps) return false;
    if (child.bottom > parent.bottom + eps) return false;
    final pa = parent.width * parent.height;
    if (pa <= 0) return false;
    final ca = child.width * child.height;
    return ca >= 0.6 * pa;
  }

  static List<String> _ancestorTypes(Element e) {
    final out = <String>[];
    e.visitAncestorElements((a) {
      out.add(a.widget.runtimeType.toString());
      return out.length < 10;
    });
    return out.reversed.toList();
  }
}

class _Kept {
  const _Kept(this.subtreeEnd, this.bounds);
  final int subtreeEnd;
  final Rect bounds;
}

