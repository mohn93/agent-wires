import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/snapshot_ext.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    ActionOverlayController.instance.reset();
  });

  testWidgets('handleSnapshot returns JSON with route and elements', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () {}, child: const Text('Tap me')),
      ),
    ));

    final resp = await SnapshotExtension.handle('ext.qa.snapshot', const {});
    expect(resp.isError(), isFalse);
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['elements'], isA<List>());
    final hasButton = (body['elements'] as List)
        .any((e) => (e as Map)['widget_type'] == 'ElevatedButton');
    expect(hasButton, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('snapshot pushes a snapshot FlashEffect', (tester) async {
    ActionOverlayController.instance.reset();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    await SnapshotExtension.handle('ext.qa.snapshot', const {});
    final flashes =
        ActionOverlayController.instance.effects.whereType<FlashEffect>();
    expect(flashes.single.kind, OverlayFlashKind.snapshot);
    await tester.pumpAndSettle();
  });
}
