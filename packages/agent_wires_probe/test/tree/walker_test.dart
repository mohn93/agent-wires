import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/tree/walker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('walker yields a Text node with its string content', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('hello')),
    ));

    final nodes = ElementTreeWalker.walkFromRoot();
    final texts = nodes.where((n) => n.widgetType == 'Text').toList();

    expect(texts, isNotEmpty);
    expect(texts.first.visibleText, equals('hello'));
  });
}
