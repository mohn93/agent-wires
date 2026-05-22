import 'package:flutter/widgets.dart';

/// Singleton state holder for the current Flutter route name.
///
/// Reading: `FlutterQAProbe.routeTracker.currentRoute`.
///
/// Wiring: pass [createObserver] into your `MaterialApp` /
/// `MaterialApp.router` `navigatorObservers` factory. A fresh
/// [NavigatorObserver] is required per navigator (Flutter asserts that an
/// observer is attached to at most one navigator at a time), so AutoRoute
/// and other multi-navigator setups must call this factory each time —
/// not reuse a single instance.
class RouteTracker {
  String? _current;
  String? get currentRoute => _current;

  /// Returns a fresh [NavigatorObserver] that forwards push/pop/replace
  /// events into this tracker. Call once per navigator.
  NavigatorObserver createObserver() => _RouteTrackerObserver(this);

  void _onPush(Route route) {
    _current = route.settings.name ?? _current;
  }

  void _onPop(Route? previousRoute) {
    _current = previousRoute?.settings.name ?? _current;
  }

  void _onReplace(Route? newRoute) {
    _current = newRoute?.settings.name ?? _current;
  }
}

class _RouteTrackerObserver extends NavigatorObserver {
  _RouteTrackerObserver(this._tracker);
  final RouteTracker _tracker;

  @override
  void didPush(Route route, Route? previousRoute) => _tracker._onPush(route);

  @override
  void didPop(Route route, Route? previousRoute) =>
      _tracker._onPop(previousRoute);

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) =>
      _tracker._onReplace(newRoute);
}
