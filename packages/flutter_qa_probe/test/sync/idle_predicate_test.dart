import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/sync/idle_predicate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('isIdle returns true after pumpAndSettle on a static screen',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('static'))));
    await tester.pumpAndSettle();
    expect(IdlePredicate.isIdle(), isTrue);
  });
}
