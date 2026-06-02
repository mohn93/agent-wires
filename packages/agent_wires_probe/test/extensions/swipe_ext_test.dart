import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/swipe_ext.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_installer.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    ActionOverlayController.instance.reset();
    ActionOverlayInstaller.reset();
  });

  testWidgets('swipe accepts absolute coordinates and returns success', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('test')),
    ));

    // Call swipe with absolute coordinates
    final resp = await tester.runAsync(() async {
      return SwipeExtension.handle('ext.qa.swipe', {
        'from_x': '300',
        'from_y': '100',
        'to_x': '50',
        'to_y': '100',
      });
    });
    await tester.pumpAndSettle();

    final body = jsonDecode(resp!.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
  });

  testWidgets('swipe with missing coordinates returns error', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('test')),
    ));

    final resp = await tester.runAsync(() async {
      return SwipeExtension.handle('ext.qa.swipe', {
        'from_x': '300',
        'from_y': '100',
        // missing to_x and to_y
      });
    });

    final body = jsonDecode(resp!.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
    expect(body['error'], contains('required'));
  });

  testWidgets('a successful swipe pushes a DragEffect from→to', (tester) async {
    ActionOverlayController.instance.reset();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    await tester.runAsync(() async {
      return SwipeExtension.handle('ext.qa.swipe', {
        'from_x': '10', 'from_y': '20', 'to_x': '10', 'to_y': '120',
      });
    });
    final fx = ActionOverlayController.instance.effects
        .whereType<DragEffect>()
        .single;
    expect(fx.from, const Offset(10, 20));
    expect(fx.to, const Offset(10, 120));
    await tester.pumpAndSettle();
  });
}
