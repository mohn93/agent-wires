import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_probe/src/extensions/enter_text_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('enter_text fills a TextField identified by element_id', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(controller: controller)),
    ));

    // Iterate ids to find the TextField — leading Listeners may take e_0..e_N.
    bool filled = false;
    for (var i = 0; i < 15 && !filled; i++) {
      final resp = await EnterTextExtension.handle('ext.qa.enter_text', {
        'element_id': 'e_$i',
        'text': 'hello',
      });
      final body = jsonDecode(resp.result!) as Map<String, dynamic>;
      if (body['success'] == true) {
        await tester.pumpAndSettle();
        if (controller.text == 'hello') filled = true;
      }
    }
    expect(controller.text, 'hello');
  });

  testWidgets('enter_text on missing element_id returns success:false', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    final resp = await EnterTextExtension.handle('ext.qa.enter_text', {
      'element_id': 'e_999',
      'text': 'hello',
    });
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
    expect(body['error'], contains('not found'));
  });

  testWidgets('enter_text with missing text param returns success:false', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    final resp = await EnterTextExtension.handle('ext.qa.enter_text', {
      'element_id': 'e_0',
    });
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
    expect(body['error'], contains('text required'));
  });

  testWidgets('enter_text with missing element_id param returns success:false', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    final resp = await EnterTextExtension.handle('ext.qa.enter_text', {
      'text': 'hello',
    });
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
    expect(body['error'], contains('element_id required'));
  });
}
