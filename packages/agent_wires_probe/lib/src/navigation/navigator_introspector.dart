import 'package:flutter/widgets.dart';

/// Walks the live Element tree to discover every active [Navigator] and
/// reports the name of each one's top-of-stack route.
///
/// This is the structural source of truth — works for declarative Navigator
/// 2.0 routers (AutoRoute, GoRouter, page-based navigation) without
/// requiring the integrator to wire a [NavigatorObserver] into every nested
/// router. The observer-based [RouteTracker] is kept as a fallback for
/// imperative routes pushed via `Navigator.pushNamed` that have no
/// corresponding Page.
class NavigatorIntrospector {
  /// Returns the current top-of-stack route name from every [Navigator]
  /// found in the live Element tree, in **deepest-first** order (so for
  /// a nested setup like AutoTabsRouter > Tab > PageView, you get
  /// `["UserProfileRoute", "AccountRoute", "MainRoute"]`).
  ///
  /// Only navigators using page-based routing (where `widget.pages` is
  /// non-empty) contribute; imperative-only navigators are silently
  /// skipped here and remain covered by the observer-based tracker.
  static List<String> collectRouteStack() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return const [];

    // Collect (depth, routeName) so we can sort deepest-first.
    final found = <_NavRoute>[];
    void visit(Element e, int depth) {
      final w = e.widget;
      if (w is Navigator && w.pages.isNotEmpty) {
        final topName = w.pages.last.name;
        if (topName != null) {
          found.add(_NavRoute(depth, topName));
        }
      }
      e.visitChildren((c) => visit(c, depth + 1));
    }

    visit(root, 0);
    found.sort((a, b) => b.depth.compareTo(a.depth));
    return found.map((n) => n.name).toList(growable: false);
  }
}

class _NavRoute {
  const _NavRoute(this.depth, this.name);
  final int depth;
  final String name;
}
