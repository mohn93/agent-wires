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

  test('app_status reports probe_attached:false for an idle session', () async {
    final session = AppSession.lazy(workingDirectory: '/tmp');
    final tools = lifecycleTools(session);
    final status = tools.firstWhere((t) => t.name == 'app_status');
    final payload = _decode(await status.handler({}));
    expect(payload['probe_attached'], isFalse,
        reason: 'an un-booted session has no live probe');
  });

  test('app_status reports probe_attached:true when the probe is alive',
      () async {
    // Distinguishes probe liveness from process liveness — the gap that made
    // a hot-restart desync look like state:ready while every call failed.
    final session = AppSession.attached(_AliveVm());
    final tools = lifecycleTools(session);
    final status = tools.firstWhere((t) => t.name == 'app_status');
    final payload = _decode(await status.handler({}));
    expect(payload['state'], 'ready');
    expect(payload['probe_attached'], isTrue);
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

  group('probe version skew warning (#6)', () {
    test('warns when the running probe differs from the expected version', () {
      final w =
          probeVersionSkewWarning(expected: '0.1.4', actual: '0.1.2');
      expect(w, isNotNull);
      expect(w, contains('0.1.2'));
      expect(w, contains('0.1.4'));
    });

    test('no warning when versions match', () {
      expect(probeVersionSkewWarning(expected: '0.1.4', actual: '0.1.4'),
          isNull);
    });

    test('no warning when the probe version is unknown (older probe)', () {
      expect(
          probeVersionSkewWarning(expected: '0.1.4', actual: null), isNull);
    });

    test('app_status surfaces probe_version and a skew warning', () async {
      final session = AppSession.attached(_SkewedProbeVm());
      final tools = lifecycleTools(session);
      final status = tools.firstWhere((t) => t.name == 'app_status');
      final payload = _decode(await status.handler({}));
      expect(payload['probe_version'], '0.0.1-old');
      expect(payload['probe_version_warning'], isNotNull);
      expect(payload['probe_version_warning'], contains('0.0.1-old'));
    });
  });

  test('app_status surfaces paused_at_start when the app is frozen (#3)',
      () async {
    // Process up, probe unreachable because the isolate never resumed: report
    // paused_at_start so a --start-stopped freeze isn't read as healthy.
    final session = AppSession.attached(_FrozenVm());
    final tools = lifecycleTools(session);
    final status = tools.firstWhere((t) => t.name == 'app_status');
    final payload = _decode(await status.handler({}));
    expect(payload['probe_attached'], isFalse);
    expect(payload['paused_at_start'], isTrue);
  });

  group('boot_app force-stop on device change (#6)', () {
    test('only a running lazy session on a different device is force-stopped',
        () {
      bool decide(bool attached, AppState s, String? cur, String req) =>
          AppSession.shouldForceStopForDevice(
            attached: attached,
            state: s,
            currentDevice: cur,
            requestedDevice: req,
          );
      expect(decide(false, AppState.ready, 'iphone', 'sim'), isTrue);
      expect(decide(false, AppState.ready, 'iphone', 'iphone'), isFalse,
          reason: 'same device — no need to restart');
      expect(decide(false, AppState.idle, null, 'sim'), isFalse,
          reason: 'nothing running to stop');
      expect(decide(true, AppState.ready, 'iphone', 'sim'), isFalse,
          reason: 'attached sessions cannot switch device');
    });
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

class _AliveVm extends VmClient {
  _AliveVm() : super.test();

  @override
  Future<bool> isProbeAlive() async => true;
}

/// Process up but isolate frozen at start: probe unreachable, paused detected.
class _FrozenVm extends VmClient {
  _FrozenVm() : super.test();

  @override
  Future<bool> isProbeAlive() async => false;

  @override
  Future<bool> isPausedAtStart() async => true;
}

/// Alive probe reporting a stale version, to exercise the skew warning path.
class _SkewedProbeVm extends VmClient {
  _SkewedProbeVm() : super.test();

  @override
  Future<bool> isProbeAlive() async => true;

  @override
  Future<String?> probeVersion() async => '0.0.1-old';
}
