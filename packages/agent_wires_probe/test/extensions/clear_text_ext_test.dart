import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/clear_text_ext.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_installer.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    ActionOverlayController.instance.reset();
    ActionOverlayInstaller.reset();
  });
  testWidgets('clear_text empties a populated TextField', (tester) async {
    final controller = TextEditingController(text: 'pre-existing');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(controller: controller)),
    ));

    // Iterate to find the TextField.
    bool cleared = false;
    for (var i = 0; i < 15 && !cleared; i++) {
      final resp = await ClearTextExtension.handle('ext.qa.clear_text', {
        'element_id': 'e_$i',
      });
      final body = jsonDecode(resp.result!) as Map<String, dynamic>;
      if (body['success'] == true) {
        await tester.pumpAndSettle();
        if (controller.text.isEmpty) cleared = true;
      }
    }
    expect(controller.text, '');
  });

  testWidgets('clear_text on missing element_id returns success:false', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    final resp = await ClearTextExtension.handle('ext.qa.clear_text', {
      'element_id': 'e_999',
    });
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
    expect(body['error'], contains('not found'));
  });

  testWidgets('clear_text with missing element_id param returns success:false', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    final resp = await ClearTextExtension.handle('ext.qa.clear_text', {});
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
    expect(body['error'], contains('element_id required'));
  });

  testWidgets('a successful clear_text highlights the field with (cleared)',
      (tester) async {
    ActionOverlayController.instance.reset();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(controller: TextEditingController(text: 'pre'))),
    ));
    for (var i = 0; i < 20; i++) {
      final resp = await ClearTextExtension.handle('ext.qa.clear_text',
          {'element_id': 'e_$i'});
      if (jsonDecode(resp.result!)['success'] == true) break;
    }
    final fx = ActionOverlayController.instance.effects
        .whereType<HighlightEffect>()
        .singleOrNull;
    expect(fx, isNotNull);
    expect(fx!.label, '(cleared)');
    await tester.pumpAndSettle();
  });
}
