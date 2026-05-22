import 'package:flutter/material.dart';
import 'package:flutter_probe/src/tree/walker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('walker captures creationLocation for a Text widget', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('hi'))));
    final nodes = ElementTreeWalker.walkFromRoot();
    final text = nodes.firstWhere((n) => n.widgetType == 'Text');
    expect(text.creationLocation, isNotNull);
    expect(text.creationLocation, contains('creation_location_test.dart'));
  });
}
