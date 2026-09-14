import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/tools/lifecycle_tools.dart';
import 'package:test/test.dart';

void main() {
  test('boot_app exposes timeout_minutes', () {
    final tool = lifecycleTools(AppSession.lazy(workingDirectory: '/x'))
        .firstWhere((t) => t.name == 'boot_app');
    final props = tool.inputSchema['properties'] as Map;
    expect(props.containsKey('timeout_minutes'), isTrue);
  });

  test('a non-numeric timeout_minutes is rejected, not ignored', () async {
    final tool = lifecycleTools(AppSession.lazy(workingDirectory: '/x'))
        .firstWhere((t) => t.name == 'boot_app');
    final res =
        await tool.handler({'timeout_minutes': 'thirty', 'wait': false});
    expect(res['isError'], isTrue);
  });
}
