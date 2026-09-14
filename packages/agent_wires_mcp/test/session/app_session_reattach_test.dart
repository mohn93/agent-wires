import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  group('reattach after a lost VM connection', () {
    test('needsReattach is true only for a ready session whose vm is lost', () {
      expect(
        AppSession.needsReattach(state: AppState.ready, connectionLost: true),
        isTrue,
      );
      expect(
        AppSession.needsReattach(state: AppState.ready, connectionLost: false),
        isFalse,
      );
      expect(
        AppSession.needsReattach(state: AppState.booting, connectionLost: true),
        isFalse,
      );
      expect(
        AppSession.needsReattach(state: AppState.exited, connectionLost: true),
        isFalse,
      );
    });

    test(
        'an attached session with a lost vm fails ensureReady with a clear '
        'message instead of handing back the dead client', () async {
      final session = AppSession.attached(_LostVm());
      await expectLater(
        session.ensureReady(),
        throwsA(predicate((e) =>
            e is StateError && e.toString().toLowerCase().contains('lost'))),
      );
    });
  });

  test('lazy sessions accept a boot timeout', () {
    final session = AppSession.lazy(
      workingDirectory: '/nonexistent',
      bootTimeout: const Duration(minutes: 30),
    );
    expect(session.bootTimeout, const Duration(minutes: 30));
  });
}

class _LostVm extends VmClient {
  _LostVm() : super.test();
  @override
  bool get isConnectionLost => true;
}
