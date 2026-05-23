import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  group('AppSession.attached', () {
    test('starts in ready state and ensureReady returns the wrapped VmClient',
        () async {
      final vm = _FakeVm();
      final session = AppSession.attached(vm);
      expect(session.state, AppState.ready);
      expect(await session.ensureReady(), same(vm));
    });

    test('dispose flips state to exited', () async {
      final session = AppSession.attached(_FakeVm());
      await session.dispose();
      expect(session.state, AppState.exited);
    });

    test('ensureReady after dispose throws StateError', () async {
      final session = AppSession.attached(_FakeVm());
      await session.dispose();
      expect(() => session.ensureReady(), throwsStateError);
    });
  });

  group('AppSession.lazy', () {
    test('starts in idle state with no vm service uri', () {
      final session = AppSession.lazy(workingDirectory: '/nonexistent');
      expect(session.state, AppState.idle);
      expect(session.vmServiceUri, isNull);
    });

    test('ensureReady on a bogus working dir flips state to exited and rethrows',
        () async {
      // flutter is on PATH in CI but the working dir doesn't exist, so
      // FlutterRunner.start will fail. We just need the state machine to
      // observe a boot failure — the specific error type isn't load-bearing.
      final session = AppSession.lazy(
        workingDirectory: '/this/does/not/exist/at/all',
      );
      await expectLater(session.ensureReady(), throwsA(isA<Object>()));
      expect(session.state, AppState.exited);
      expect(session.lastError, isNotNull);
    });
  });
}

class _FakeVm extends VmClient {
  _FakeVm() : super.test();
}
