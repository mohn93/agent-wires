import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/swipe_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('swipe accepts absolute coordinates and returns success', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('test')),
    ));

    // Call swipe with absolute coordinates
    final resp = await tester.runAsync(() async {
      return SwipeExtension.handle('ext.qa.swipe', {
        'from_x': '300',
        'from_y': '100',
        'to_x': '50',
        'to_y': '100',
      });
    });
    await tester.pumpAndSettle();

    final body = jsonDecode(resp!.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
  });

  testWidgets('swipe with missing coordinates returns error', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('test')),
    ));

    final resp = await tester.runAsync(() async {
      return SwipeExtension.handle('ext.qa.swipe', {
        'from_x': '300',
        'from_y': '100',
        // missing to_x and to_y
      });
    });

    final body = jsonDecode(resp!.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
    expect(body['error'], contains('required'));
  });
}
