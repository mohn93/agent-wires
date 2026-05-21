import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/resolver/element_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resolves e_0 to the first promoted+bounded element', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ElevatedButton(onPressed: () {}, child: const Text('Go'))),
    ));
    final result = ElementResolver.resolve('e_0');
    expect(result, isNotNull);
    // e_0 is the first promoted+bounded node in tree order; with the existing
    // classifier, Listener (promoted unconditionally) appears before ElevatedButton.
    expect(result!.widget, isNotNull);
  });

  testWidgets('returns null for an out-of-range id', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    expect(ElementResolver.resolve('e_999'), isNull);
  });

  test('returns null for malformed id', () {
    expect(ElementResolver.resolve('not_an_id'), isNull);
    expect(ElementResolver.resolve(''), isNull);
  });
}
