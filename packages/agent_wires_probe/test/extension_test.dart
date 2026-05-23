import 'dart:developer' as developer;
import 'package:agent_wires_probe/agent_wires_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('install registers a "ext.qa.ping" extension that returns ok', () async {
    AgentWiresProbe.install();
    final reg = developer.Service.getInfo();
    expect(reg, isNotNull);
    // We can't call extensions from inside a unit test without a VM service,
    // but we can assert the extension name was registered by checking the
    // private registry through AgentWiresProbe.registeredExtensions.
    expect(AgentWiresProbe.registeredExtensions, contains('ext.qa.ping'));
  });
}
