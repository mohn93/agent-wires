import 'dart:convert';
import 'package:agent_wires_probe/src/extensions/set_overlay_ext.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = ActionOverlayController.instance;
  setUp(c.reset);

  test('enabled:false disables the controller and echoes state', () async {
    final resp = await SetOverlayExtension.handle(
        'ext.qa.set_overlay', {'enabled': 'false'});
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(body['enabled'], isFalse);
    expect(c.enabled, isFalse);
  });

  test('enabled:true re-enables the controller', () async {
    c.setEnabled(false);
    await SetOverlayExtension.handle('ext.qa.set_overlay', {'enabled': 'true'});
    expect(c.enabled, isTrue);
  });

  test('missing enabled returns success:false', () async {
    final resp =
        await SetOverlayExtension.handle('ext.qa.set_overlay', const {});
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
  });
}
