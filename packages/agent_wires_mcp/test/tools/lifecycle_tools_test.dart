import 'dart:convert';

import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/tools/lifecycle_tools.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  test('lifecycleTools exposes boot_app, app_status, and stop_app', () {
    final tools = lifecycleTools(AppSession.attached(_FakeVm()));
    expect(tools.map((t) => t.name).toSet(),
        {'boot_app', 'app_status', 'stop_app'});
  });

  test('boot_app on an already-attached session returns state=ready', () async {
    final tools = lifecycleTools(AppSession.attached(_FakeVm()));
    final boot = tools.firstWhere((t) => t.name == 'boot_app');
    final payload = _decode(await boot.handler({}));
    expect(payload['state'], 'ready');
  });

  test('app_status reflects the session state without booting', () async {
    final session = AppSession.lazy(workingDirectory: '/tmp');
    final tools = lifecycleTools(session);
    final status = tools.firstWhere((t) => t.name == 'app_status');
    final payload = _decode(await status.handler({}));
    expect(payload['state'], 'idle');
    expect(session.state, AppState.idle,
        reason: 'app_status must not trigger a boot');
  });

  test('stop_app flips an attached session to exited', () async {
    final session = AppSession.attached(_FakeVm());
    final tools = lifecycleTools(session);
    final stop = tools.firstWhere((t) => t.name == 'stop_app');
    final payload = _decode(await stop.handler({}));
    expect(payload['state'], 'exited');
    expect(session.state, AppState.exited);
  });
}

Map<String, dynamic> _decode(Map<String, dynamic> toolResult) {
  final text = ((toolResult['content'] as List).first as Map)['text'] as String;
  return jsonDecode(text) as Map<String, dynamic>;
}

class _FakeVm extends VmClient {
  _FakeVm() : super.test();
}
