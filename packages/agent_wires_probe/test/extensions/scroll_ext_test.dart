import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/scroll_ext.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_installer.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    ActionOverlayController.instance.reset();
    ActionOverlayInstaller.reset();
  });

  testWidgets('scroll down moves the ScrollPosition', (tester) async {
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

    final resp = await tester.runAsync(() async {
      return ScrollExtension.handle('ext.qa.scroll', {
        'direction': 'down',
        'distance': '200',
      });
    });
    await tester.pumpAndSettle();

    final body = jsonDecode(resp!.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(controller.position.pixels, greaterThan(0));
  });

  testWidgets('a successful scroll pushes a DragEffect', (tester) async {
    ActionOverlayController.instance.reset();
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

    await tester.runAsync(() async {
      return ScrollExtension.handle('ext.qa.scroll', {
        'direction': 'down',
        'distance': '200',
      });
    });

    expect(ActionOverlayController.instance.effects.whereType<DragEffect>(),
        isNotEmpty);
    await tester.pumpAndSettle();
  });
}
