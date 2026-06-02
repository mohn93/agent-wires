import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/tools/overlay_tools.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

AppSession _session() => AppSession.attached(_FakeVm());

void main() {
  test('overlayTools returns 1 tool named set_action_overlay', () {
    final tools = overlayTools(_session());
    expect(tools, hasLength(1));
    expect(tools.first.name, 'set_action_overlay');
  });

  test('set_action_overlay schema requires enabled (boolean)', () {
    final tool = overlayTools(_session()).first;
    final required = (tool.inputSchema['required'] as List).cast<String>();
    expect(required, contains('enabled'));
    final props = tool.inputSchema['properties'] as Map<String, dynamic>;
    expect((props['enabled'] as Map)['type'], 'boolean');
  });
}

// A minimal stub. VmClient handlers never get invoked in these schema-only tests.
class _FakeVm implements VmClient {
  @override
  // ignore: avoid_annotating_with_dynamic
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
