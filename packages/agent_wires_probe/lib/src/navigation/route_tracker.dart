import 'package:flutter/widgets.dart';

import 'navigator_introspector.dart';

/// Tracks active route names across one or more navigators.
///
/// Two data sources, merged at read time:
///   1. [NavigatorIntrospector] walks the live Element tree at snapshot
///      time and returns the top page name from every [Navigator] using
///      page-based routing (declarative Navigator 2.0 — AutoRoute,
///      GoRouter, etc.). This needs **no integrator wiring**.
///   2. [createObserver] returns [NavigatorObserver]s for the integrator
///      to attach to any imperative navigators they want covered. Used as
///      a fallback for routes pushed via `Navigator.pushNamed` that have
///      no Page representation.
///
/// Reading:
///   - `currentRoute` — top-of-stack of the deepest live navigator, or
///     the most recently fired observer if no introspectable navigators
///     are present.
///   - `routeStack` — every navigator's current top-of-stack route. From
///     introspection (deepest-first) plus any observer-only routes that
///     do not duplicate what introspection already found.
///
/// Wiring is optional. For an AutoRoute / GoRouter / page-based app you
/// can skip [createObserver] entirely — introspection covers it.
class RouteTracker {
  /// Insertion order doubles as "most recently active first" because we
  /// remove and re-insert an observer at the front whenever it fires.
  final List<_RouteTrackerObserver> _observers = <_RouteTrackerObserver>[];

  String? get currentRoute {
    final stack = routeStack;
    return stack.isEmpty ? null : stack.first;
  }

  List<String> get routeStack {
    final introspected = NavigatorIntrospector.collectRouteStack();
    final seen = introspected.toSet();
    final observed = <String>[
      for (final o in _observers)
        if (o.currentRoute != null && seen.add(o.currentRoute!))
          o.currentRoute!,
    ];
    return [...introspected, ...observed];
  }

  /// Returns a fresh [NavigatorObserver] for one navigator. Call once
  /// per navigator in your `navigatorObservers` factory **if** you have
  /// imperative routes (`Navigator.pushNamed` etc.) that introspection
  /// cannot see. For page-based routers (AutoRoute, GoRouter) this is
  /// optional — introspection already covers them.
  NavigatorObserver createObserver() => _RouteTrackerObserver(this);

  void _onActivity(_RouteTrackerObserver o) {
    _observers.remove(o);
    _observers.insert(0, o);
  }
}

class _RouteTrackerObserver extends NavigatorObserver {
  _RouteTrackerObserver(this._tracker);
  final RouteTracker _tracker;

  String? _currentRoute;
  String? get currentRoute => _currentRoute;

  void _update(String? name) {
    if (name == null) return;
    _currentRoute = name;
    _tracker._onActivity(this);
  }

  @override
  void didPush(Route route, Route? previousRoute) =>
      _update(route.settings.name);

  @override
  void didPop(Route route, Route? previousRoute) =>
      _update(previousRoute?.settings.name);

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) =>
      _update(newRoute?.settings.name);
}
