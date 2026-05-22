import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/flutter_qa_probe.dart';
import 'package:flutter_qa_probe/src/extensions/wait_for_route_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wait_for_route resolves once the named route becomes current', (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [FlutterQAProbe.routeTracker.createObserver()],
      initialRoute: '/',
      routes: {
        '/': (_) => const Scaffold(body: Text('home')),
        '/cart': (_) => const Scaffold(body: Text('cart')),
      },
    ));

    final future = tester.runAsync(() => WaitForRouteExtension.handle('ext.qa.wait_for_route', {
      'route': '/cart',
      'timeout_ms': '2000',
    }));

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/cart');
    await tester.pumpAndSettle();

    final resp = await future;
    final body = jsonDecode(resp!.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(body['matched'], isTrue);
  });
}
