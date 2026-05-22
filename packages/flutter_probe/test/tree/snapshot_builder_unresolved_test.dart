import 'package:flutter/material.dart';
import 'package:flutter_probe/src/tree/snapshot_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GestureDetector with no text or icon lands in unresolved[]', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          onTap: () {},
          child: const SizedBox(width: 50, height: 50, child: ColoredBox(color: Color(0xFF000000))),
        ),
      ),
    ));

    final snap = SnapshotBuilder.build();
    final unresolvedGD = snap.unresolved.where((e) => e.widgetType == 'GestureDetector');
    expect(unresolvedGD, isNotEmpty);
    // It should NOT be in elements[] since it has no label
    final resolvedGD = snap.elements.where((e) => e.widgetType == 'GestureDetector' && e.label != null);
    expect(resolvedGD, isEmpty);
  });

  testWidgets('button with a Text label stays in elements[], not unresolved', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ElevatedButton(onPressed: () {}, child: const Text('Go'))),
    ));
    final snap = SnapshotBuilder.build();
    expect(snap.elements.any((e) => e.label == 'Go'), isTrue);
    expect(snap.unresolved.any((e) => e.label == 'Go'), isFalse);
  });
}
