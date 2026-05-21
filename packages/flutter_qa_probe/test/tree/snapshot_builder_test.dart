import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/tree/snapshot_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('snapshot returns one element for a labeled ElevatedButton', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(onPressed: () {}, child: const Text('Checkout')),
        ),
      ),
    ));

    final snap = SnapshotBuilder.build();
    final buttons = snap.elements.where((e) => e.widgetType == 'ElevatedButton').toList();
    expect(buttons, hasLength(1));
    expect(buttons.first.label, 'Checkout');
    expect(buttons.first.role, 'button');
    expect(buttons.first.fingerprint, startsWith('f_'));
  });

  testWidgets('Padding and Center do not appear in elements', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Padding(padding: EdgeInsets.all(8), child: Center(child: Text('hi'))),
    ));
    final snap = SnapshotBuilder.build();
    expect(snap.elements.where((e) => e.widgetType == 'Padding'), isEmpty);
    expect(snap.elements.where((e) => e.widgetType == 'Center'), isEmpty);
  });
}
