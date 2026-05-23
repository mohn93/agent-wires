import 'package:flutter/widgets.dart';

/// Tracks active route names across one or more navigators.
///
/// Reading:
///   - `currentRoute` — the route name from the most recently active
///     navigator (last didPush/didPop/didReplace anywhere in the app).
///   - `routeStack` — every navigator's current top-of-stack route, in
///     order of last activity (most recent first). For AutoRoute tab
///     setups this is `["MainRoute", "DomainsRoute"]` or similar —
///     letting the agent tell apart screens that share the same outer
///     route.
///
/// Wiring: pass [createObserver] into every `navigatorObservers` factory
/// in your app — once for the root navigator, once for each nested
/// (per-tab, per-drawer) navigator. A fresh observer is required per
/// navigator because Flutter asserts that one observer is attached to at
/// most one navigator at a time.
class RouteTracker {
  /// Insertion order doubles as "most recently active first" because we
  /// remove and re-insert an observer at the front whenever it fires.
  final List<_RouteTrackerObserver> _observers = <_RouteTrackerObserver>[];

  /// Route name from the most recently active observer, or null when no
  /// navigator has fired yet.
  String? get currentRoute => _observers.isEmpty
      ? null
      : _observers.first.currentRoute;

  /// Current top-of-stack route name from every navigator that has at
  /// least one observed event. Most recently active first.
  List<String> get routeStack => _observers
      .map((o) => o.currentRoute)
      .whereType<String>()
      .toList(growable: false);

  /// Returns a fresh [NavigatorObserver] for one navigator. Call once
  /// per navigator in your `navigatorObservers` factory.
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
