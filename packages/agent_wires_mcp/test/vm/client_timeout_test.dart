import 'dart:async';

import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  group('per-call timeout', () {
    test('a caller-supplied timeout overrides callTimeout for that call',
        () async {
      // wait_for_element(timeout_ms: 30000) legitimately runs inside the probe
      // for 30 s. With the default 30 s callTimeout that read as a dead socket
      // and latched the whole session as lost (field report, 2026-09-14).
      final vm = _SlowVm(delay: const Duration(milliseconds: 300));
      final result = await vm.callExtensionWithTimeout(
        'ext.qa.wait_for_element',
        {'label': 'x'},
        const Duration(seconds: 2),
      );
      expect(result['ok'], isTrue);
      expect(vm.isConnectionLost, isFalse);
    });
  });

  group('timeout with a live connection', () {
    test('does NOT latch the connection when the VM still answers', () async {
      final vm = _SlowVm(delay: const Duration(seconds: 2), alive: true);
      await expectLater(
        vm.callExtension('ext.qa.snapshot'),
        throwsA(isA<VmCallTimeoutException>()),
      );
      expect(vm.isConnectionLost, isFalse,
          reason: 'a slow extension is not a dead socket');
      // The next call must still go through.
      final ok = await _SlowVm(delay: Duration.zero, alive: true)
          .callExtension('ext.qa.ping');
      expect(ok['ok'], isTrue);
    });

    test('latches the connection when the VM does not answer either', () async {
      final vm = _SlowVm(delay: const Duration(seconds: 2), alive: false);
      await expectLater(
        vm.callExtension('ext.qa.snapshot'),
        throwsA(isA<VmConnectionLostException>()),
      );
      expect(vm.isConnectionLost, isTrue);
    });
  });
}

/// Raw call resolves after [delay]; [alive] is what the liveness probe says.
class _SlowVm extends VmClient {
  _SlowVm({required this.delay, this.alive = true}) : super.test();
  final Duration delay;
  final bool alive;

  @override
  Duration get callTimeout => const Duration(milliseconds: 100);

  @override
  Future<bool> isConnectionAlive() async => alive;

  @override
  Future<Map<String, dynamic>> rawCallExtension(
      String name, Map<String, String> args) async {
    await Future<void>.delayed(delay);
    return {'ok': true};
  }
}
