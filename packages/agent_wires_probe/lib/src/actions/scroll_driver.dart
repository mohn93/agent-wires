import 'package:flutter/widgets.dart';

/// Scroll direction for [ScrollDriver]. Named [ScrollDir] to avoid clashing
/// with Flutter's own [ScrollDirection] from package:flutter/rendering.dart.
enum ScrollDir { up, down, left, right }

class ScrollDriver {
  /// Scrolls the best matching [Scrollable] reachable from [root].
  ///
  /// Searches [root]'s descendants first; if none qualify (e.g. the caller
  /// passed a leaf row whose list is an *ancestor*), walks up to the nearest
  /// enclosing [Scrollable] of the requested axis.
  static Future<bool> scrollIn(Element root, ScrollDir direction, double pixels) async {
    final state = _selectScrollable(root, direction) ??
        _ancestorScrollable(root, direction);
    if (state == null) return false;
    return _drive(state, direction, pixels);
  }

  static Future<bool> scrollAnyVisible(ScrollDir direction, double pixels) async {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return false;
    final state = _selectScrollable(root, direction);
    if (state == null) return false;
    return _drive(state, direction, pixels);
  }

  static Future<bool> _drive(
    ScrollableState state,
    ScrollDir direction,
    double pixels,
  ) async {
    // Defensive: selection already filters to usable positions, but never let
    // an unattached position throw ("Null check operator used on a null value")
    // out of the action handler.
    final position = _usablePosition(state);
    if (position == null) return false;
    if (!_axisMatches(state, direction)) return false;
    final delta = switch (direction) {
      ScrollDir.up => -pixels,
      ScrollDir.down => pixels,
      ScrollDir.left => -pixels,
      ScrollDir.right => pixels,
    };
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    // Use jumpTo (synchronous) so the driver works inside flutter_test's
    // runAsync context where the vsync ticker is not driven by real time.
    // animateTo would deadlock because its TickerProvider requires the test
    // binding to pump frames, which runAsync does not do.
    position.jumpTo(target);
    return true;
  }

  /// Whether [state]'s scroll axis matches the requested [direction].
  static bool _axisMatches(ScrollableState state, ScrollDir direction) {
    final isVertical = state.axisDirection == AxisDirection.down ||
        state.axisDirection == AxisDirection.up;
    final wantsVertical =
        direction == ScrollDir.up || direction == ScrollDir.down;
    return isVertical == wantsVertical;
  }

  /// Returns [state]'s [ScrollPosition] only when it is actually drivable:
  /// attached to a viewport with real dimensions. Offstage / not-yet-laid-out
  /// scrollables (e.g. DevicePreview's tools list, lazy IndexedStack tabs)
  /// return null so they never shadow the on-screen content list — and so
  /// accessing `_position!` / `_pixels!` can never throw.
  static ScrollPosition? _usablePosition(ScrollableState state) {
    try {
      final position = state.position;
      if (!position.hasPixels || !position.haveDimensions) return null;
      return position;
    } catch (_) {
      // ScrollableState.position is `_position!`; a transiently-detached
      // scrollable throws here rather than returning null.
      return null;
    }
  }

  /// Picks the best drivable scrollable in [root]'s subtree for [direction]:
  /// usable position + matching axis, preferring the largest viewport (the
  /// on-screen content list rather than a small chrome strip).
  static ScrollableState? _selectScrollable(Element root, ScrollDir direction) {
    ScrollableState? best;
    double bestExtent = -1;
    void consider(ScrollableState state) {
      final position = _usablePosition(state);
      if (position == null) return;
      if (!_axisMatches(state, direction)) return;
      if (position.viewportDimension > bestExtent) {
        bestExtent = position.viewportDimension;
        best = state;
      }
    }

    void visit(Element e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        consider(e.state as ScrollableState);
      }
      e.visitChildren(visit);
    }

    visit(root);
    return best;
  }

  /// Nearest enclosing drivable [Scrollable] of the requested axis, for when a
  /// leaf element was passed whose list is an ancestor.
  static ScrollableState? _ancestorScrollable(Element element, ScrollDir direction) {
    final wantsVertical =
        direction == ScrollDir.up || direction == ScrollDir.down;
    final axis = wantsVertical ? Axis.vertical : Axis.horizontal;
    final state = Scrollable.maybeOf(element, axis: axis);
    if (state == null) return null;
    return _usablePosition(state) == null ? null : state;
  }
}
