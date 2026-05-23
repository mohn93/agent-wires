import 'package:agent_wires_probe/agent_wires_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AgentWiresProbe.install is a no-op when called twice', () {
    AgentWiresProbe.install();
    AgentWiresProbe.install();
    expect(AgentWiresProbe.isInstalled, isTrue);
  });
}
