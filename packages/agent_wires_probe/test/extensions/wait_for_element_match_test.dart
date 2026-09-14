import 'dart:convert';
import 'package:agent_wires_probe/src/extensions/wait_for_element_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>> _wait(
    WidgetTester tester, Map<String, String> params) async {
  final resp = await tester.runAsync(
      () => WaitForElementExtension.handle('ext.qa.wait_for_element', params));
  return jsonDecode(resp!.result!) as Map<String, dynamic>;
}

Widget _button(String text) => MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () {}, child: Text(text)),
      ),
    );

void main() {
  testWidgets('match=substring matches case-insensitively at word boundaries',
      (tester) async {
    await tester.pumpWidget(_button('Find your domain'));
    final body = await _wait(tester, {
      'label': 'your DOMAIN',
      'role': 'button',
      'match': 'substring',
      'timeout_ms': '500',
    });
    expect(body['matched'], isTrue);
    expect(body['match'], 'substring');
    expect(body['element_id'], startsWith('e_'));
  });

  testWidgets('substring mode does not match inside a word', (tester) async {
    await tester.pumpWidget(_button('Book now'));
    final body = await _wait(
        tester, {'label': 'OK', 'match': 'substring', 'timeout_ms': '200'});
    expect(body['matched'], isFalse);
  });

  testWidgets('the default is exact-only', (tester) async {
    await tester.pumpWidget(_button('Find your domain'));
    final body =
        await _wait(tester, {'label': 'your domain', 'timeout_ms': '200'});
    expect(body['matched'], isFalse);
  });

  testWidgets('an exact label wins over a substring match', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ElevatedButton(
              onPressed: () {}, child: const Text('Domains and more')),
          ElevatedButton(onPressed: () {}, child: const Text('Domains')),
        ]),
      ),
    ));
    final body = await _wait(
        tester, {'label': 'Domains', 'match': 'substring', 'timeout_ms': '500'});
    expect(body['matched'], isTrue);
    expect(body['label'], 'Domains');
    expect(body['match'], 'exact');
  });

  testWidgets('a role-only wait reports match=role', (tester) async {
    await tester.pumpWidget(_button('Go'));
    final body = await _wait(tester, {'role': 'button', 'timeout_ms': '200'});
    expect(body['matched'], isTrue);
    expect(body['match'], 'role');
  });

  testWidgets('an unknown match mode is rejected', (tester) async {
    await tester.pumpWidget(_button('Go'));
    final body = await _wait(tester, {'label': 'Go', 'match': 'fuzzy'});
    expect(body['success'], isFalse);
  });
}
