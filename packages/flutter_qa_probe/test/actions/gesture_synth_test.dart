import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/actions/gesture_synth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapAt triggers onTap on a Button at given coords', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => tapped++,
            child: const Text('Hit'),
          ),
        ),
      ),
    ));

    final ro = tester.renderObject(find.byType(ElevatedButton));
    final box = ro as RenderBox;
    final center = box.localToGlobal(box.size.center(Offset.zero));

    await GestureSynth.tapAt(center);
    await tester.pumpAndSettle();

    expect(tapped, 1);
  });
}
