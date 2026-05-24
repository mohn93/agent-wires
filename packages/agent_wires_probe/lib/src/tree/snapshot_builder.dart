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

  /// Diagnostic counts from the most recent [keptNodes] run. The agent
  /// reads this via SnapshotRecord._debug to verify the route-scoping
  /// pass actually ran (and which navigators contributed). Updated in
  /// place each call.
  static OcclusionStats _lastOcclusionStats = OcclusionStats.empty();
  static OcclusionStats get lastOcclusionStats => _lastOcclusionStats;

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
      debug: {'occlusion': _lastOcclusionStats.toJson()},
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
    var theatersFound = 0;
    var entriesProcessed = 0;
    var entriesDropped = 0;
    final theaterDetails = <Map<String, dynamic>>[];
    final viewport = _viewportRect();
    if (viewport == null) {
      _lastOcclusionStats = OcclusionStats(
        theatersFound: 0,
        entriesProcessed: 0,
        entriesDropped: 0,
        viewportFound: false,
      );
      return occluded;
    }

    for (var i = 0; i < raw.length; i++) {
      if (raw[i].widgetType != '_Theater') continue;
      theatersFound++;
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
      entriesProcessed += entries.length;
      if (entries.length < 2) continue;

      // "Covering" is judged against THIS theater's own box, not the global
      // window. device_preview (and any nested Navigator) lays its pages out
      // smaller than physicalSize — measuring against the full window made an
      // 870px page read as 91% of a 956px viewport and never "cover".
      final theaterRect = raw[i].bounds ?? viewport;

      // Per-entry cover check + a description, so we can see WHY an entry
      // did or didn't register as covering (its largest node's bounds, the
      // transition/page wrappers above it, etc.).
      final covers = <bool>[];
      final entryDescs = <Map<String, dynamic>>[];
      for (var k = 0; k < entries.length; k++) {
        final c =
            _subtreeCoversViewport(raw, subtreeEnd, entries[k], theaterRect);
        covers.add(c);
        entryDescs.add(_describeEntry(raw, subtreeEnd, entries[k], c));
      }

      int? topCoveringIdx;
      for (var k = entries.length - 1; k >= 0; k--) {
        if (covers[k]) {
          topCoveringIdx = k;
          break;
        }
      }

      theaterDetails.add({
        'theater_depth': theaterDepth,
        'entry_count': entries.length,
        'top_covering_idx': topCoveringIdx,
        'entries': entryDescs,
      });

      if (topCoveringIdx == null) continue;

      // Mark every entry before the topmost covering one — they are buried
      // under an opaque page and the user can't see them.
      for (var k = 0; k < topCoveringIdx; k++) {
        entriesDropped++;
        final start = entries[k];
        final end = subtreeEnd[start];
        for (var m = start; m <= end; m++) {
          occluded[m] = true;
        }
      }
    }
    _lastOcclusionStats = OcclusionStats(
      theatersFound: theatersFound,
      entriesProcessed: entriesProcessed,
      entriesDropped: entriesDropped,
      viewportFound: true,
      details: theaterDetails,
    );
    return occluded;
  }

  /// Returns true when any node in [root]'s subtree *encloses* [target]
  /// (within 2px slack on every edge). Containment — not area — so a page
  /// that's been parallax-shifted out from under the top route (same area,
  /// translated left) no longer counts as covering. [target] is the owning
  /// theater's box, so device_preview / nested navigators are measured
  /// against their real viewport rather than the full window.
  static bool _subtreeCoversViewport(
    List<RawNode> raw,
    List<int> subtreeEnd,
    int root,
    Rect target,
  ) {
    if (target.width <= 0 || target.height <= 0) return false;
    const eps = 2.0;
    for (var i = root; i <= subtreeEnd[root]; i++) {
      final b = raw[i].bounds;
      if (b == null) continue;
      if (b.left <= target.left + eps &&
          b.top <= target.top + eps &&
          b.right >= target.right - eps &&
          b.bottom >= target.bottom - eps) {
        return true;
      }
    }
    return false;
  }

  /// Diagnostic description of one overlay entry: the first few descendant
  /// widget types (to spot the page / transition wrappers — e.g.
  /// CupertinoPageTransition, Scaffold) and the largest-area bounded node
  /// in its subtree (the candidate the cover test keys off). Surfaced via
  /// OcclusionStats so we can see why a pushed page isn't matching.
  static Map<String, dynamic> _describeEntry(
    List<RawNode> raw,
    List<int> subtreeEnd,
    int root,
    bool covers,
  ) {
    final childTypes = <String>[];
    for (var i = root + 1;
        i <= subtreeEnd[root] && childTypes.length < 6;
        i++) {
      childTypes.add(raw[i].widgetType);
    }
    Rect? maxRect;
    String? maxType;
    var maxArea = -1.0;
    for (var i = root; i <= subtreeEnd[root]; i++) {
      final b = raw[i].bounds;
      if (b == null) continue;
      final area = b.width * b.height;
      if (area > maxArea) {
        maxArea = area;
        maxRect = b;
        maxType = raw[i].widgetType;
      }
    }
    return {
      'entry_type': raw[root].widgetType,
      'depth': raw[root].depth,
      'subtree_size': subtreeEnd[root] - root + 1,
      'covers': covers,
      'child_types': childTypes,
      if (maxRect != null)
        'max_node': {
          'type': maxType,
          'x': maxRect.left.round(),
          'y': maxRect.top.round(),
          'w': maxRect.width.round(),
          'h': maxRect.height.round(),
        },
    };
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

/// Counts from one occlusion pass — surfaced into the snapshot as a `_debug`
/// field so the agent can verify the route-scoping ran, and (when it
/// didn't drop anything) tell us *why* (no overlay entries seen, no
/// covering page detected, etc.).
class OcclusionStats {
  const OcclusionStats({
    required this.theatersFound,
    required this.entriesProcessed,
    required this.entriesDropped,
    required this.viewportFound,
    this.details = const [],
  });

  factory OcclusionStats.empty() => const OcclusionStats(
        theatersFound: 0,
        entriesProcessed: 0,
        entriesDropped: 0,
        viewportFound: false,
      );

  /// Number of `_Theater` nodes seen — one per Navigator's Overlay.
  /// Zero means we never found an overlay; the route-scoping pass had
  /// nothing to do.
  final int theatersFound;

  /// Total `_OverlayEntryWidget` children counted across all theaters.
  /// In a single-page app this is 1; with a pushed route it's at least 2.
  final int entriesProcessed;

  /// Entries marked occluded (their subtree dropped from snapshot).
  /// Zero with theaters > 1 and entries > 2 means no entry passed the
  /// "covers the viewport" check — probe build is wrong or the pages
  /// aren't laid out viewport-sized for some reason.
  final int entriesDropped;

  /// False when the viewport couldn't be determined (rare; means the
  /// MediaQuery / View metrics weren't available at snapshot time).
  final bool viewportFound;

  /// Per-theater breakdown — only theaters with >= 2 overlay entries (where
  /// a drop decision is actually made). Each item: {theater_depth,
  /// entry_count, top_covering_idx, entries:[{entry_type, depth,
  /// subtree_size, covers, child_types, max_node}]}. Diagnostic only.
  final List<Map<String, dynamic>> details;

  Map<String, dynamic> toJson() => {
        'theaters_found': theatersFound,
        'entries_processed': entriesProcessed,
        'entries_dropped': entriesDropped,
        'viewport_found': viewportFound,
        if (details.isNotEmpty) 'theaters': details,
      };
}

