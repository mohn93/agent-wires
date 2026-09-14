import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/tools/sync_tools.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  _extraTests();
  test('wait_for_element forwards a call timeout longer than timeout_ms',
      () async {
    final vm = _RecordingVm();
    final tool = syncTools(AppSession.attached(vm))
        .firstWhere((t) => t.name == 'wait_for_element');
    await tool.handler({'label': 'x', 'timeout_ms': 30000});
    expect(vm.lastTimeout, isNotNull);
    expect(vm.lastTimeout!, greaterThan(const Duration(seconds: 30)));
  });

  test(
      'wait_for_idle with no timeout_ms still forwards a timeout above the '
      'probe default', () async {
    final vm = _RecordingVm();
    final tool = syncTools(AppSession.attached(vm))
        .firstWhere((t) => t.name == 'wait_for_idle');
    await tool.handler({});
    expect(vm.lastTimeout, isNotNull);
    expect(vm.lastTimeout!, greaterThan(const Duration(seconds: 10)));
  });
}

void _extraTests() {
  test('callTimeoutFor accepts doubles and numeric strings, and caps the wait',
      () {
    expect(callTimeoutFor(30000.0, probeDefaultMs: 5000),
        const Duration(milliseconds: 30000) + const Duration(seconds: 10));
    expect(callTimeoutFor('2500', probeDefaultMs: 5000),
        const Duration(milliseconds: 2500) + const Duration(seconds: 10));
    expect(callTimeoutFor('nope', probeDefaultMs: 5000),
        const Duration(milliseconds: 5000) + const Duration(seconds: 10));
    expect(
        callTimeoutFor(30000000, probeDefaultMs: 5000),
        const Duration(milliseconds: maxProbeWaitMs) +
            const Duration(seconds: 10));
  });
}

class _RecordingVm extends VmClient {
  _RecordingVm() : super.test();
  Duration? lastTimeout;

  @override
  Future<Map<String, dynamic>> callExtensionWithTimeout(
      String name, Map<String, dynamic>? args, Duration timeout) async {
    lastTimeout = timeout;
    return {'success': true};
  }
}
