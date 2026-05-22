import 'package:flutter/widgets.dart';

/// Scroll direction for [ScrollDriver]. Named [ScrollDir] to avoid clashing
/// with Flutter's own [ScrollDirection] from package:flutter/rendering.dart.
enum ScrollDir { up, down, left, right }

class ScrollDriver {
  static Future<bool> scrollIn(Element root, ScrollDir direction, double pixels) async {
    final scrollable = _firstDescendantScrollable(root);
    if (scrollable == null) return false;
    return _drive(scrollable, direction, pixels);
  }

  static Future<bool> scrollAnyVisible(ScrollDir direction, double pixels) async {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return false;
    final scrollable = _firstDescendantScrollable(root);
    if (scrollable == null) return false;
    return _drive(scrollable, direction, pixels);
  }

  static Future<bool> _drive(
    ScrollableState state,
    ScrollDir direction,
    double pixels,
  ) async {
    final position = state.position;
    final isVertical = state.axisDirection == AxisDirection.down ||
        state.axisDirection == AxisDirection.up;
    final delta = switch (direction) {
      ScrollDir.up => -pixels,
      ScrollDir.down => pixels,
      ScrollDir.left => -pixels,
      ScrollDir.right => pixels,
    };
    if (isVertical &&
        (direction == ScrollDir.left || direction == ScrollDir.right)) {
      return false;
    }
    if (!isVertical &&
        (direction == ScrollDir.up || direction == ScrollDir.down)) {
      return false;
    }
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

  static ScrollableState? _firstDescendantScrollable(Element root) {
    ScrollableState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is ScrollableState) {
        found = e.state as ScrollableState;
        return;
      }
      e.visitChildren(visit);
    }
    if (root is StatefulElement && root.state is ScrollableState) {
      return root.state as ScrollableState;
    }
    visit(root);
    return found;
  }
}
