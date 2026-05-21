import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/navigation/route_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tracker reports the current named route', (tester) async {
    final tracker = RouteTracker();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [tracker],
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
}
