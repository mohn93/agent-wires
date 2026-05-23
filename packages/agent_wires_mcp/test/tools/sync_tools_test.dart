import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/tools/sync_tools.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

AppSession _session() => AppSession.attached(_FakeVm());

void main() {
  test('syncTools returns 3 tools with the expected names', () {
    final tools = syncTools(_session());
    final names = tools.map((t) => t.name).toSet();
    expect(names, {'wait_for_idle', 'wait_for_route', 'wait_for_element'});
  });

  test('wait_for_route schema requires route', () {
    final t = syncTools(_session()).firstWhere((t) => t.name == 'wait_for_route');
    expect((t.inputSchema['required'] as List), contains('route'));
  });
}

class _FakeVm implements VmClient {
  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}
