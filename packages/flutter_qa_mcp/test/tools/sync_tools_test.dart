import 'package:flutter_qa_mcp/src/tools/sync_tools.dart';
import 'package:flutter_qa_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  test('syncTools returns 3 tools with the expected names', () {
    final tools = syncTools(_FakeVm());
    final names = tools.map((t) => t.name).toSet();
    expect(names, {'wait_for_idle', 'wait_for_route', 'wait_for_element'});
  });

  test('wait_for_route schema requires route', () {
    final t = syncTools(_FakeVm()).firstWhere((t) => t.name == 'wait_for_route');
    expect((t.inputSchema['required'] as List), contains('route'));
  });
}

class _FakeVm implements VmClient {
  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}
