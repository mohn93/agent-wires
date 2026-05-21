import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/press_back_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('press_back pops the top route', (tester) async {
    await tester.pumpWidget(MaterialApp(
      initialRoute: '/',
      routes: {
        '/': (_) => const Scaffold(body: Text('home')),
        '/next': (_) => const Scaffold(body: Text('next')),
      },
    ));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/next');
    await tester.pumpAndSettle();
    expect(find.text('next'), findsOneWidget);

    final resp = await PressBackExtension.handle('ext.qa.press_back', const {});
    await tester.pumpAndSettle();
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(find.text('home'), findsOneWidget);
  });
}
