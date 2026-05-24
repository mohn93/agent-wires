import 'package:flutter/widgets.dart';

/// Walks the live Element tree to discover every active [Navigator] and
/// returns the full page-based back-stack for each one, deepest-first.
///
/// This is the structural source of truth — works for declarative Navigator
/// 2.0 routers (AutoRoute, GoRouter, page-based navigation) without
/// requiring the integrator to wire a [NavigatorObserver] into every nested
/// router. The observer-based [RouteTracker] is kept as a fallback for
/// imperative routes pushed via `Navigator.pushNamed` that have no
/// corresponding Page.
class NavigatorIntrospector {
  /// Returns every named route currently on screen across every page-based
  /// [Navigator] in the live tree, in **deepest-first** order.
  ///
  /// AutoRoute holds the back-stack as a single Navigator with a `pages`
  /// list (`[Domains, DomainDetails, DomainRecords]`); we iterate that
  /// list reversed so the deepest leaf comes first. Nested navigators (a
  /// tab inside an AutoTabsRouter that itself contains a stack) contribute
  /// their own pages above the parent's. Result for the agent's case:
  /// `["DomainRecordsRoute", "DomainDetailsRoute", "DomainsRoute",
  ///   "MainRoute"]`.
  ///
  /// Only navigators using page-based routing (where `widget.pages` is
  /// non-empty) contribute; imperative-only navigators are silently
  /// skipped here and remain covered by the observer-based tracker.
  static List<String> collectRouteStack() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return const [];

    // Collect (depth, pageIndex, routeName). Sort key is (-depth, -pageIndex)
    // so deeper navigators come first and within one navigator the topmost
    // page comes before the ones beneath it.
    final found = <_NavRoute>[];
    void visit(Element e, int depth) {
      final w = e.widget;
      if (w is Navigator && w.pages.isNotEmpty) {
        for (var i = 0; i < w.pages.length; i++) {
          final name = w.pages[i].name;
          if (name != null) found.add(_NavRoute(depth, i, name));
        }
      }
      e.visitChildren((c) => visit(c, depth + 1));
    }

    visit(root, 0);
    found.sort((a, b) {
      final byDepth = b.depth.compareTo(a.depth);
      if (byDepth != 0) return byDepth;
      return b.pageIndex.compareTo(a.pageIndex);
    });
    return found.map((n) => n.name).toList(growable: false);
  }
}

class _NavRoute {
  const _NavRoute(this.depth, this.pageIndex, this.name);
  final int depth;
  final int pageIndex;
  final String name;
}
