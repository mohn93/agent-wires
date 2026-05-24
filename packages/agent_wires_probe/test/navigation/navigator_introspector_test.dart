import 'package:agent_wires_probe/src/navigation/navigator_introspector.dart';
import 'package:agent_wires_probe/src/navigation/route_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'introspector picks up nested page-based navigator without any observer',
      (tester) async {
    // This is the bug from the agent feedback: AutoRoute/GoRouter style
    // setups stack page-based Navigators (one outer + one per tab). The
    // old observer-only RouteTracker missed nested routes unless the
    // integrator wired createObserver() into every nested router.
    // Introspection should find them all with zero wiring.
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        pages: const [
          MaterialPage(name: 'MainRoute', child: SizedBox()),
        ],
        onDidRemovePage: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(NavigatorIntrospector.collectRouteStack(), contains('MainRoute'));
  });

  testWidgets(
      'introspector returns deepest-first for nested page-based navigators',
      (tester) async {
    // Outer navigator at MainRoute; inner nested navigator at UserProfileRoute.
    // The agent expects to see UserProfileRoute first (where the user is)
    // with MainRoute behind it (the screen that hosts the tab).
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        pages: [
          MaterialPage(
            name: 'MainRoute',
            child: Navigator(
              pages: const [
                MaterialPage(name: 'AccountRoute', child: SizedBox()),
                MaterialPage(name: 'UserProfileRoute', child: SizedBox()),
              ],
              onDidRemovePage: (_) {},
            ),
          ),
        ],
        onDidRemovePage: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    final stack = NavigatorIntrospector.collectRouteStack();
    // Full back-stack: inner navigator's pages reversed (deepest first),
    // then outer navigator's. AccountRoute is in the stack underneath
    // UserProfileRoute even though only UserProfileRoute is the active leaf.
    expect(stack, ['UserProfileRoute', 'AccountRoute', 'MainRoute']);
  });

  testWidgets(
      'introspector returns the full back-stack within a single AutoRoute-style navigator',
      (tester) async {
    // AutoRoute keeps the navigation history as a `pages` list on one
    // Navigator. Pushing 3 screens deep means `pages = [A, B, C]`.
    // The introspector must return all three, not just C.
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        pages: const [
          MaterialPage(name: 'DomainsRoute', child: SizedBox()),
          MaterialPage(name: 'DomainDetailsRoute', child: SizedBox()),
          MaterialPage(name: 'DomainRecordsRoute', child: SizedBox()),
        ],
        onDidRemovePage: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(NavigatorIntrospector.collectRouteStack(),
        ['DomainRecordsRoute', 'DomainDetailsRoute', 'DomainsRoute']);
  });

  testWidgets(
      'RouteTracker.routeStack merges introspected routes + observer-only routes',
      (tester) async {
    final tracker = RouteTracker();
    await tester.pumpWidget(MaterialApp(
      // Observer attached only to the root (legacy imperative wiring).
      navigatorObservers: [tracker.createObserver()],
      home: Navigator(
        pages: const [
          MaterialPage(name: 'MainRoute', child: SizedBox()),
          MaterialPage(name: 'UserProfileRoute', child: SizedBox()),
        ],
        onDidRemovePage: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    // Introspection sees the page-based inner Navigator's top
    // (UserProfileRoute). Observer fires for the imperative outer
    // (MaterialApp default) push of '/'.
    expect(tracker.routeStack, contains('UserProfileRoute'));
    expect(tracker.currentRoute, 'UserProfileRoute');
  });

  test('introspector returns empty when no rootElement exists', () {
    // No widget tree pumped — rootElement is null. Should not throw.
    expect(NavigatorIntrospector.collectRouteStack(), isEmpty);
  });
}
