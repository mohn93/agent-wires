import 'package:agent_wires_probe/agent_wires_probe.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('install(actionOverlay:false) registers set_overlay and disables it',
      () {
    AgentWiresProbe.install(actionOverlay: false);
    expect(AgentWiresProbe.registeredExtensions, contains('ext.qa.set_overlay'));
    expect(ActionOverlayController.instance.enabled, isFalse);
  });
}
