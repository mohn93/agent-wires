import 'dart:convert';

import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/tools/lifecycle_tools.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  test('lifecycleTools exposes all six lifecycle tools', () {
    final tools = lifecycleTools(AppSession.attached(_FakeVm()));
    expect(tools.map((t) => t.name).toSet(), {
      'list_devices',
      'boot_app',
      'app_status',
      'stop_app',
      'hot_reload',
      'hot_restart',
    });
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

  test('hot_restart in attached mode returns a helpful error', () async {
    final session = AppSession.attached(_FakeVm());
    final tools = lifecycleTools(session);
    final restart = tools.firstWhere((t) => t.name == 'hot_restart');
    final result = await restart.handler({});
    expect(result['isError'], isTrue);
    final text = ((result['content'] as List).first as Map)['text'] as String;
    expect(text, contains('attached'),
        reason: 'attached sessions cannot restart the flutter process');
  });

  test('hot_reload in attached mode delegates to VmClient.reloadSources',
      () async {
    final vm = _RecordingVm();
    final session = AppSession.attached(vm);
    final tools = lifecycleTools(session);
    final reload = tools.firstWhere((t) => t.name == 'hot_reload');
    final payload = _decode(await reload.handler({}));
    expect(vm.reloadCalls, 1);
    expect(payload['mode'], 'vm_service');
    expect(payload['success'], isTrue);
  });

  test('boot_app with wait:false returns immediately without booting',
      () async {
    // Use a lazy session that points at a bogus directory — if boot_app
    // waited synchronously this would block for the timeout. With wait:false
    // we return state="booting" immediately and the agent can poll.
    final session = AppSession.lazy(workingDirectory: '/does/not/exist');
    final tools = lifecycleTools(session);
    final boot = tools.firstWhere((t) => t.name == 'boot_app');
    final stopwatch = Stopwatch()..start();
    final payload = _decode(await boot.handler({'wait': false}));
    stopwatch.stop();
    expect(payload['state'], anyOf('booting', 'exited'),
        reason: 'should return without waiting for boot to complete');
    expect(stopwatch.elapsed.inSeconds, lessThan(2),
        reason: 'fire-and-forget should return promptly');
  });

  test(
      'boot_app default (wait omitted) still blocks and surfaces the error',
      () async {
    // wait defaults to true, so this should propagate the boot failure
    // as an isError tool result. Uses a bogus dir; flutter exits quickly
    // with "No pubspec.yaml" so this isn't slow.
    final session = AppSession.lazy(workingDirectory: '/does/not/exist');
    final tools = lifecycleTools(session);
    final boot = tools.firstWhere((t) => t.name == 'boot_app');
    final result = await boot.handler({});
    expect(result['isError'], isTrue);
  });
}

class _RecordingVm extends VmClient {
  _RecordingVm() : super.test();
  int reloadCalls = 0;

  @override
  Future<Map<String, dynamic>> reloadSources() async {
    reloadCalls++;
    return {'success': true};
  }
}

Map<String, dynamic> _decode(Map<String, dynamic> toolResult) {
  final text = ((toolResult['content'] as List).first as Map)['text'] as String;
  return jsonDecode(text) as Map<String, dynamic>;
}

class _FakeVm extends VmClient {
  _FakeVm() : super.test();
}
