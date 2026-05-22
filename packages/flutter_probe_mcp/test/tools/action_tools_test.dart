import 'package:flutter_probe_mcp/src/tools/action_tools.dart';
import 'package:flutter_probe_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  test('actionTools returns 7 tools with the expected names', () {
    final tools = actionTools(_FakeVm());
    final names = tools.map((t) => t.name).toSet();
    expect(names, {
      'tap', 'long_press', 'swipe', 'enter_text', 'clear_text', 'scroll', 'press_back',
    });
  });

  test('tap schema requires element_id', () {
    final tap = actionTools(_FakeVm()).firstWhere((t) => t.name == 'tap');
    expect((tap.inputSchema['required'] as List), contains('element_id'));
  });

  test('swipe schema requires from_x/from_y/to_x/to_y', () {
    final swipe = actionTools(_FakeVm()).firstWhere((t) => t.name == 'swipe');
    final required = (swipe.inputSchema['required'] as List).cast<String>();
    expect(required, containsAll(['from_x', 'from_y', 'to_x', 'to_y']));
  });

  test('enter_text schema requires element_id and text', () {
    final et = actionTools(_FakeVm()).firstWhere((t) => t.name == 'enter_text');
    final required = (et.inputSchema['required'] as List).cast<String>();
    expect(required, containsAll(['element_id', 'text']));
  });
}

// A minimal stub. VmClient handlers never get invoked in these schema-only tests.
class _FakeVm implements VmClient {
  @override
  // ignore: avoid_annotating_with_dynamic
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
