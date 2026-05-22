import 'package:flutter/material.dart';
import 'package:flutter_probe/src/navigation/route_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tracker reports the current named route', (tester) async {
    final tracker = RouteTracker();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [tracker.createObserver()],
      initialRoute: '/',
      routes: {
        '/': (_) => const Scaffold(body: Text('root')),
        '/cart': (_) => const Scaffold(body: Text('cart')),
      },
    ));
    expect(tracker.currentRoute, '/');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/cart');
    await tester.pumpAndSettle();

    expect(tracker.currentRoute, '/cart');
  });

  testWidgets(
      'routeStack reflects nested navigators independently (tab-app pattern)',
      (tester) async {
    // AutoRoute (and any IndexedStack-of-Navigators tab UI) keeps the
    // outer route fixed and switches tabs by pushing into nested
    // Navigators. Each Navigator gets its own observer; routeStack
    // surfaces "where am I in each navigator?" so the agent can tell
    // tabs apart.
    final tracker = RouteTracker();
    final outerKey = GlobalKey<NavigatorState>();
    final tabKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(MaterialApp(
      navigatorKey: outerKey,
      navigatorObservers: [tracker.createObserver()],
      home: Scaffold(
        body: Navigator(
          key: tabKey,
          observers: [tracker.createObserver()],
          onGenerateRoute: (s) => MaterialPageRoute(
            settings: s,
            builder: (_) => const Text('initial-tab'),
          ),
          initialRoute: 'home-tab',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Outer navigator pushed '/' (its MaterialApp home).
    // Inner navigator pushed 'home-tab'.
    expect(tracker.routeStack, containsAll(['/', 'home-tab']));

    // Simulate a tab switch on the inner navigator.
    tabKey.currentState!.pushReplacementNamed('domains-tab');
    await tester.pumpAndSettle();

    expect(tracker.currentRoute, 'domains-tab');
    expect(tracker.routeStack.first, 'domains-tab');
    expect(tracker.routeStack, contains('/'));
  });
}
