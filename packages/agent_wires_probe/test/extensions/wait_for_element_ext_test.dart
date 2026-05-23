import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/wait_for_element_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wait_for_element finds a button by label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () {}, child: const Text('Checkout')),
      ),
    ));

    final resp = await tester.runAsync(() => WaitForElementExtension.handle('ext.qa.wait_for_element', {
      'label': 'Checkout',
      'timeout_ms': '1000',
    }));
    final body = jsonDecode(resp!.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(body['matched'], isTrue);
    expect(body['element_id'], startsWith('e_'));
  });

  testWidgets('wait_for_element returns matched:false after timeout', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('nothing'))));

    final resp = await tester.runAsync(() => WaitForElementExtension.handle('ext.qa.wait_for_element', {
      'label': 'NoSuchLabel',
      'timeout_ms': '300',
    }));
    final body = jsonDecode(resp!.result!) as Map<String, dynamic>;
    expect(body['matched'], isFalse);
  });
}
