import 'package:flutter/widgets.dart';

class RouteTracker extends NavigatorObserver {
  String? _current;
  String? get currentRoute => _current;

  @override
  void didPush(Route route, Route? previousRoute) {
    _current = route.settings.name ?? _current;
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _current = previousRoute?.settings.name ?? _current;
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _current = newRoute?.settings.name ?? _current;
  }
}
