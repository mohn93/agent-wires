import 'package:agent_wires_probe/src/actions/gesture_synth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('swipe up drags a ListView (move events carry a real delta)',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
        ),
      ),
    ));

    await GestureSynth.swipe(const Offset(200, 500), const Offset(200, 100));
    await tester.pumpAndSettle();

    expect(controller.position.pixels, greaterThan(100),
        reason: 'a 400px drag must move the list, not be ignored');
  });
}
