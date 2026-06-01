import 'dart:async';

import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  test('throws ArgumentError for unsupported URI scheme', () async {
    expect(
      () => VmClient.connect(Uri.parse('ftp://localhost:1234')),
      throwsArgumentError,
    );
  });

  // The ws-URI normalisation is exercised indirectly by e2e tests against a
  // real device; here we just confirm http/ws/https/wss are all accepted by
  // the entry point (the actual socket connect will then fail, but that's
  // beyond the input-validation contract).
  test('accepts http, https, ws, wss schemes without throwing ArgumentError',
      () async {
    for (final uri in [
      'http://127.0.0.1:55555/abc=/',
      'https://127.0.0.1:55555/abc=/',
      'ws://127.0.0.1:55555/abc=/ws',
      'wss://127.0.0.1:55555/abc=/ws',
    ]) {
      try {
        await VmClient.connect(Uri.parse(uri));
      } on ArgumentError {
        fail('connect should not reject $uri');
      } catch (_) {
        // Connection failures are expected — no real VM on that port.
      }
    }
  });

  group('stale-isolate recovery (hot restart)', () {
    test('callExtension rebinds and retries once after a Sentinel error',
        () async {
      // A hot restart tears down the QA isolate and starts a new one. The
      // first call against the stale isolate id comes back as a collected
      // Sentinel; the client must re-resolve the live isolate and retry,
      // so the agent's tool call transparently succeeds instead of failing
      // for the rest of the session (the field report's #1 blocker).
      final vm = _RestartingVm();
      final result = await vm.callExtension('ext.qa.snapshot');
      expect(result['ok'], isTrue);
      expect(vm.rebinds, 1, reason: 'must re-resolve the isolate exactly once');
      expect(vm.rawCalls, 2, reason: 'first call fails stale, retry succeeds');
    });

    test('callExtension does NOT retry on an ordinary (non-stale) error',
        () async {
      final vm = _OrdinaryErrorVm();
      await expectLater(
          vm.callExtension('ext.qa.tap'), throwsA(isA<StateError>()));
      expect(vm.rawCalls, 1, reason: 'a non-stale error is not retried');
      expect(vm.rebinds, 0);
    });

    test('stale error + failed rebind surfaces a clear, non-raw error',
        () async {
      // If the probe is truly gone (app exited, or restarted without calling
      // AgentWiresProbe.install), the agent should get an actionable message
      // — not the cryptic raw "[Sentinel kind: Collected]" (#9).
      final vm = _GoneProbeVm();
      await expectLater(
        vm.callExtension('ext.qa.snapshot'),
        throwsA(predicate((e) =>
            e is StateError && e.toString().toLowerCase().contains('probe'))),
      );
    });
  });

  group('connection-lost fail-fast (#1)', () {
    test('callExtension fails fast (does not hang) when the socket is dead',
        () async {
      // A half-open socket leaves the underlying RPC future hanging forever.
      // The client must bound it with a per-call timeout and surface a clear
      // VmConnectionLostException instead of wedging for minutes (#1).
      final vm = _HangingVm();
      final sw = Stopwatch()..start();
      await expectLater(
        vm.callExtension('ext.qa.snapshot'),
        throwsA(isA<VmConnectionLostException>()),
      );
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: 'must fail fast, not await the dead socket');
    });

    test('a lost connection is latched — later calls fail immediately',
        () async {
      final vm = _HangingVm();
      await expectLater(vm.callExtension('ext.qa.snapshot'),
          throwsA(isA<VmConnectionLostException>()));
      await expectLater(vm.callExtension('ext.qa.snapshot'),
          throwsA(isA<VmConnectionLostException>()));
      expect(vm.rawCalls, 1,
          reason: 'once lost, no further attempts hit the dead socket');
      expect(vm.isConnectionLost, isTrue);
    });

    test('a disposed-connection error fails fast and does NOT rebind',
        () async {
      // "Service connection disposed" is a dead connection, not a stale
      // isolate. Rebinding would also hang on the same dead socket, so the
      // client must fail fast without attempting a rebind.
      final vm = _DisposedConnectionVm();
      await expectLater(
        vm.callExtension('ext.qa.tap'),
        throwsA(isA<VmConnectionLostException>()),
      );
      expect(vm.rebinds, 0,
          reason: 'rebind would hang on the same dead socket');
    });

    test('isProbeAlive returns false fast once the connection is lost',
        () async {
      final vm = _HangingVm();
      await expectLater(vm.callExtension('x'),
          throwsA(isA<VmConnectionLostException>()));
      expect(await vm.isProbeAlive(), isFalse,
          reason: 'must not re-hang probing a dead connection');
    });
  });

  group('probeVersion (#6)', () {
    test('returns the version the probe reports over ping', () async {
      final vm = _PingVm('0.1.4');
      expect(await vm.probeVersion(), '0.1.4');
    });

    test('returns null when the probe predates version reporting', () async {
      final vm = _PingVm(null);
      expect(await vm.probeVersion(), isNull);
    });

    test('returns null (does not throw) when the call fails', () async {
      expect(await _GoneProbeVm().probeVersion(), isNull);
    });
  });

  group('isProbeAlive', () {
    test('returns false when no isolate has ever been bound', () async {
      expect(await VmClient.test().isProbeAlive(), isFalse);
    });

    test('re-resolves and rebinds when the bound isolate is gone', () async {
      // After a hot restart, app_status should still report the probe as
      // attached (it lives in the new isolate) and the client should rebind
      // to it so the next tool call is fast.
      final vm = _RebindableVm();
      expect(await vm.isProbeAlive(), isTrue);
      expect(vm.isolateId, 'isolates/fresh',
          reason: 'isProbeAlive should heal the binding to the live isolate');
    });

    test('returns false when re-resolution finds no QA isolate', () async {
      expect(await _GoneProbeVm().isProbeAlive(), isFalse);
    });
  });
}

/// First raw call returns a collected Sentinel; rebind succeeds; retry works.
class _RestartingVm extends VmClient {
  _RestartingVm() : super.test();
  int rawCalls = 0;
  int rebinds = 0;

  @override
  Future<Map<String, dynamic>> rawCallExtension(
      String name, Map<String, String> args) async {
    rawCalls++;
    if (rawCalls == 1) {
      throw StateError('[Sentinel kind: Collected, valueAsString: <collected>]');
    }
    return {'ok': true};
  }

  @override
  Future<String> resolveQaIsolate() async {
    rebinds++;
    return 'isolates/new';
  }
}

/// Raw call throws a plain error that has nothing to do with a dead isolate.
class _OrdinaryErrorVm extends VmClient {
  _OrdinaryErrorVm() : super.test();
  int rawCalls = 0;
  int rebinds = 0;

  @override
  Future<Map<String, dynamic>> rawCallExtension(
      String name, Map<String, String> args) async {
    rawCalls++;
    throw StateError('element not found: e_99');
  }

  @override
  Future<String> resolveQaIsolate() async {
    rebinds++;
    return 'isolates/new';
  }
}

/// Always stale, and re-resolution fails — the probe is truly gone.
class _GoneProbeVm extends VmClient {
  _GoneProbeVm() : super.test();

  @override
  Future<Map<String, dynamic>> rawCallExtension(
          String name, Map<String, String> args) async =>
      throw StateError('[Sentinel kind: Collected]');

  @override
  Future<String> resolveQaIsolate() async =>
      throw StateError('no isolate has ext.qa.* extensions registered');
}

/// The bound isolate is gone but a fresh one is available.
class _RebindableVm extends VmClient {
  _RebindableVm() : super.test();

  @override
  Future<String> resolveQaIsolate() async => 'isolates/fresh';
}

/// rawCallExtension never completes — simulates a dead/half-open socket where
/// the RPC future hangs forever. A short [callTimeout] makes the fail-fast
/// behaviour observable in the test's wall-clock budget.
class _HangingVm extends VmClient {
  _HangingVm() : super.test();
  int rawCalls = 0;

  @override
  Duration get callTimeout => const Duration(milliseconds: 100);

  @override
  Future<Map<String, dynamic>> rawCallExtension(
      String name, Map<String, String> args) {
    rawCalls++;
    return Completer<Map<String, dynamic>>().future; // never completes
  }
}

/// Returns a ping payload carrying (or omitting) a probe_version field.
class _PingVm extends VmClient {
  _PingVm(this.version) : super.test();
  final String? version;

  @override
  Future<Map<String, dynamic>> rawCallExtension(
      String name, Map<String, String> args) async {
    return {'ok': true, if (version != null) 'probe_version': version};
  }
}

/// Raw call throws the VM-service "connection disposed" error.
class _DisposedConnectionVm extends VmClient {
  _DisposedConnectionVm() : super.test();
  int rebinds = 0;

  @override
  Future<Map<String, dynamic>> rawCallExtension(
      String name, Map<String, String> args) async {
    throw StateError('Service connection disposed');
  }

  @override
  Future<String> resolveQaIsolate() async {
    rebinds++;
    return 'isolates/new';
  }
}
