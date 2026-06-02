import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/long_press_ext.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_installer.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    ActionOverlayController.instance.reset();
    ActionOverlayInstaller.reset();
  });

  testWidgets('long_press on a GestureDetector triggers onLongPress', (tester) async {
    // This test probes the action, not the overlay. Turn the overlay off so
    // installing the host can't shift the element ids the loop resolves by.
    ActionOverlayController.instance.setEnabled(false);
    var longPresses = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          onLongPress: () => longPresses++,
          child: const SizedBox(width: 100, height: 100, child: ColoredBox(color: Color(0xFF000000))),
        ),
      ),
    ));

    // Try a range of ids to find the GestureDetector (Listener widgets may appear first).
    bool triggered = false;
    for (var i = 0; i < 10 && !triggered; i++) {
      final resp = await tester.runAsync(
        () => LongPressExtension.handle('ext.qa.long_press', {
          'element_id': 'e_$i',
          'duration_ms': '600',
        }),
      );
      if (resp != null) {
        final body = jsonDecode(resp.result!) as Map<String, dynamic>;
        if (body['success'] == true) {
          await tester.pumpAndSettle();
          if (longPresses > 0) triggered = true;
        }
      }
    }
    expect(longPresses, greaterThanOrEqualTo(1));
  });

  testWidgets('a successful long_press pushes a TapEffect with longPress:true',
      (tester) async {
    ActionOverlayController.instance.reset();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          onLongPress: () {},
          child: const SizedBox(
              width: 100,
              height: 100,
              child: ColoredBox(color: Color(0xFF000000))),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      final resp = await tester.runAsync(
        () => LongPressExtension.handle('ext.qa.long_press', {
          'element_id': 'e_$i',
          'duration_ms': '600',
        }),
      );
      if (resp != null && jsonDecode(resp.result!)['success'] == true) break;
    }
    final tapEffects = ActionOverlayController.instance.effects
        .whereType<TapEffect>()
        .toList();
    expect(tapEffects, isNotEmpty);
    expect(tapEffects.first.longPress, isTrue);
    await tester.pumpAndSettle();
  });
}
