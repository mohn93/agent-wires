import 'package:flutter/widgets.dart';
import '../probe.dart';
import 'classifier.dart';
import 'element_record.dart';
import 'fingerprint.dart';
import 'raw_node.dart';
import 'role_inference.dart';
import 'state_inference.dart';
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

  /// Identity-set of Elements that live beneath an opaque pushed route.
  /// Populated each [keptNodes] call. RoleInference reads this so its
  /// descendant-text walk skips occluded subtrees and a surviving ancestor
  /// (a root Listener etc.) doesn't pick up labels from buried pages.
  static final Set<Element> _occludedElements = <Element>{};
  static Set<Element> get occludedElements => _occludedElements;

  /// Walks the live tree, applies the snapshot's classify+dedup rules, and
  /// returns the kept nodes in the same DFS-derived order the snapshot uses
  /// to assign `e_<idx>` ids. ElementResolver shares this so resolving
  /// `e_4` always points to the same element the snapshot reported at index
  /// 4, even after the dedup pass drops most of the gesture chain inside a
  /// button.
  static List<RawNode> keptNodes() {
    final raw = ElementTreeWalker.walkFromRoot();
    final n = raw.length;

    final subtreeEnd = List<int>.filled(n, 0);
    for (var i = n - 1; i >= 0; i--) {
      var j = i + 1;
      while (j < n && raw[j].depth > raw[i].depth) {
        j = subtreeEnd[j] + 1;
      }
      subtreeEnd[i] = j - 1;
    }

    // Pushed routes don't unmount what's beneath them — Flutter keeps prior
    // routes alive so the back-swipe parallax can render. The walker sees
    // every layout-active element including the ones from underlying
    // routes (FAB items from MainRoute showing up in a DomainDetails
    // snapshot, etc.). Mark elements inside an occluded overlay entry so
    // the snapshot only reports what the user actually sees. RoleInference
    // also needs the element-keyed set so its descendant-text walk
    // doesn't pull labels from occluded subtrees into a surviving ancestor.
    final occluded = _computeOccluded(raw, subtreeEnd);
    _occludedElements
      ..clear()
      ..addAll([
        for (var i = 0; i < n; i++)
          if (occluded[i]) raw[i].element,
      ]);

    final promoted = List<bool>.filled(n, false);
    for (var i = 0; i < n; i++) {
      if (occluded[i]) continue;
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
    // 1. Same-bounds-as-ancestor: a promoted descendant whose bounds sit
    //    inside, and cover ≥60% of, a kept ancestor's bounds is plumbing
    //    for that ancestor. Catches the gesture chain inside a button.
    //
    // 2. Generic-with-named-descendant: a Listener/GestureDetector/InkWell
    //    that has a named promoted descendant in its subtree is plumbing
    //    for that descendant. Catches Scaffold-level Listeners covering
    //    the viewport when buttons live inside.
    final keptStack = <_Kept>[];
    final out = <RawNode>[];

    for (var i = 0; i < n; i++) {
      while (keptStack.isNotEmpty && keptStack.last.subtreeEnd < i) {
        keptStack.removeLast();
      }
      if (!promoted[i]) continue;

      final node = raw[i];

      var subsumed = false;
      for (final k in keptStack) {
        if (_containedAndSimilar(node.bounds!, k.bounds)) {
          subsumed = true;
          break;
        }
      }
      if (subsumed) continue;

      if (_genericGesture.contains(node.widgetType)) {
        var hasNamedDescendant = false;
        for (var j = i + 1; j <= subtreeEnd[i]; j++) {
          if (!promoted[j]) continue;
          if (!_genericGesture.contains(raw[j].widgetType)) {
            hasNamedDescendant = true;
            break;
          }
        }
        // Only drop this generic wrapper as "plumbing" if it covers most
        // of the viewport — a Scaffold-level Listener with a button
        // nested deep inside it. Card-sized wrappers (DNS rows, invoice
        // rows, anything user-authored) are kept so the agent can target
        // the whole row, with the inner buttons surviving as separate
        // actions.
        if (hasNamedDescendant && _coversMostOfViewport(node.bounds!)) {
          continue;
        }
      }

      // Rule 3: TextField wraps EditableText with padding+border, so the
      // bounds don't satisfy the ≥60% area test in rule 1. Drop the
      // EditableText when a TextField / TextFormField is in the kept
      // ancestor chain. Custom PIN/OTP widgets that wrap EditableText
      // directly (no TextField in between) skip rule 3 and survive.
      if (node.widgetType == 'EditableText' &&
          keptStack.any((k) =>
              k.widgetType == 'TextField' || k.widgetType == 'TextFormField')) {
        continue;
      }

      out.add(node);
      keptStack.add(_Kept(subtreeEnd[i], node.bounds!, node.widgetType));
    }

    return out;
  }

  static SnapshotRecord build() {
    final elements = <ElementRecord>[];
    final unresolved = <ElementRecord>[];
    final kept = keptNodes();

    for (var cursor = 0; cursor < kept.length; cursor++) {
      final node = kept[cursor];
      final ancestors = _ancestorTypes(node.element);
      final inferred = RoleInference.infer(node.element);
      final fp = Fingerprint.compute(
        creationLocation: node.creationLocation,
        widgetType: node.widgetType,
        ancestorTypes: ancestors,
        siblingIndex: node.siblingIndex,
        visibleText: inferred.label,
      );

      // State of the widget itself (Switch.value, Checkbox.value, etc.).
      // A second pass below copies state up from a kept descendant when this
      // is null, so a labelled ListTile wrapping a Switch reports "on"/"off"
      // on the labelled entry directly.
      final state = StateInference.infer(node.element.widget);

      final record = ElementRecord(
        id: 'e_$cursor',
        fingerprint: fp,
        widgetType: node.widgetType,
        role: inferred.role,
        label: inferred.label,
        labelSource: inferred.labelSource.name,
        state: state,
        bounds: node.bounds,
        creationLocation: node.creationLocation,
        enabled: true,
      );
      if (inferred.label != null) {
        elements.add(record);
      } else {
        unresolved.add(record);
      }
    }

    _hoistStateFromContainedDescendants([...elements, ...unresolved]);

    final media = MediaQueryData.fromView(
        WidgetsBinding.instance.platformDispatcher.views.first);
    return SnapshotRecord(
      route: AgentWiresProbe.routeTracker.currentRoute,
      routeStack: AgentWiresProbe.routeTracker.routeStack,
      viewport: media.size,
      elements: elements,
      unresolved: unresolved,
    );
  }

  /// SwitchListTile and friends emit two kept entries in our snapshot — a
  /// labelled ListTile (no state) and an unlabelled Switch (with state).
  /// Walking the live element tree from the ListTile to find the Switch is
  /// expensive (Material InkWell stacks 25+ plumbing layers in between), so
  /// we work over the already-denoised kept set instead: for each stateful
  /// record (R), find the smallest-bounds containing record without state
  /// and hoist R's state up to it. O(N²) but N is typically <200.
  static void _hoistStateFromContainedDescendants(List<ElementRecord> records) {
    for (final stateful in records) {
      if (stateful.state == null || stateful.bounds == null) continue;
      ElementRecord? bestParent;
      double bestParentArea = double.infinity;
      for (final candidate in records) {
        if (identical(candidate, stateful)) continue;
        if (candidate.state != null) continue;
        final pBounds = candidate.bounds;
        if (pBounds == null) continue;
        if (!_containsRect(pBounds, stateful.bounds!)) continue;
        final area = pBounds.width * pBounds.height;
        if (area < bestParentArea) {
          bestParentArea = area;
          bestParent = candidate;
        }
      }
      if (bestParent != null) bestParent.state = stateful.state;
    }
  }

  static bool _containsRect(Rect outer, Rect inner) {
    const eps = 2.0;
    return inner.left >= outer.left - eps &&
        inner.top >= outer.top - eps &&
        inner.right <= outer.right + eps &&
        inner.bottom <= outer.bottom + eps;
  }

  /// Walks the linear DFS node array looking for `_Theater` nodes (the
  /// inner widget of every [Overlay], so one per [Navigator]). For each
  /// theater, finds its direct `_OverlayEntryWidget` children — these are
  /// the navigator's overlay entries (one per page/route plus modal
  /// barriers). Iterates them from topmost downward to find the first one
  /// that is "covering" (its subtree contains a node whose bounds equal
  /// the viewport). Everything in earlier entries is marked occluded.
  ///
  /// Non-covering entries above the topmost covering one (dialogs, snack
  /// bars, semi-transparent overlays) and the covering entry itself
  /// remain visible. Below the covering entry, everything is dropped.
  static List<bool> _computeOccluded(
      List<RawNode> raw, List<int> subtreeEnd) {
    final occluded = List<bool>.filled(raw.length, false);
    final viewport = _viewportRect();
    if (viewport == null) return occluded;

    for (var i = 0; i < raw.length; i++) {
      if (raw[i].widgetType != '_Theater') continue;
      final theaterDepth = raw[i].depth;
      // Collect direct _OverlayEntryWidget children. visitChildren order
      // matches insertion order on Overlay (bottom-first; last is topmost).
      final entries = <int>[];
      for (var j = i + 1; j <= subtreeEnd[i]; j++) {
        if (raw[j].depth == theaterDepth + 1 &&
            raw[j].widgetType == '_OverlayEntryWidget') {
          entries.add(j);
        }
      }
      if (entries.length < 2) continue;

      int? topCoveringIdx;
      for (var k = entries.length - 1; k >= 0; k--) {
        if (_subtreeCoversViewport(raw, subtreeEnd, entries[k], viewport)) {
          topCoveringIdx = k;
          break;
        }
      }
      if (topCoveringIdx == null) continue;

      // Mark every entry before the topmost covering one — they are buried
      // under an opaque page and the user can't see them.
      for (var k = 0; k < topCoveringIdx; k++) {
        final start = entries[k];
        final end = subtreeEnd[start];
        for (var m = start; m <= end; m++) {
          occluded[m] = true;
        }
      }
    }
    return occluded;
  }

  /// Returns true when any node in [root]'s subtree has bounds covering
  /// at least 98% of [viewport]. The 2% slack handles status bars / safe
  /// areas that an opaque page sometimes doesn't paint over.
  static bool _subtreeCoversViewport(
    List<RawNode> raw,
    List<int> subtreeEnd,
    int root,
    Rect viewport,
  ) {
    final viewportArea = viewport.width * viewport.height;
    if (viewportArea <= 0) return false;
    final threshold = viewportArea * 0.98;
    for (var i = root; i <= subtreeEnd[root]; i++) {
      final b = raw[i].bounds;
      if (b == null) continue;
      // Must roughly cover the full viewport AND start near origin —
      // a viewport-sized list scrolled mid-screen isn't a covering page.
      if (b.left > viewport.left + 2) continue;
      if (b.top > viewport.top + 2) continue;
      final area = b.width * b.height;
      if (area >= threshold) return true;
    }
    return false;
  }

  static Rect? _viewportRect() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    if (size.width <= 0 || size.height <= 0) return null;
    return Offset.zero & size;
  }

  /// A generic wrapper this large is almost certainly framework plumbing
  /// (Scaffold's internal Listener, MaterialApp's overlay) rather than a
  /// user-authored card. Below this threshold we treat it as a real
  /// target and let it survive even when it has named descendants.
  static bool _coversMostOfViewport(Rect r) {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    final viewportArea = size.width * size.height;
    if (viewportArea <= 0) return false;
    final wrapperArea = r.width * r.height;
    return wrapperArea >= 0.7 * viewportArea;
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
  const _Kept(this.subtreeEnd, this.bounds, this.widgetType);
  final int subtreeEnd;
  final Rect bounds;
  final String widgetType;
}

