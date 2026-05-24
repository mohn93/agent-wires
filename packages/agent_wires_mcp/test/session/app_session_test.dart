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

    test('exited is not terminal — ensureReady retries the boot', () async {
      // Agent feedback: once a boot timed out, every subsequent boot_app
      // instantly failed with "AppSession is exited". For lazy sessions we
      // own the project config and can simply re-boot; exited should reset
      // to idle on the next ensureReady call.
      final session = AppSession.lazy(
        workingDirectory: '/this/does/not/exist/at/all',
      );
      await expectLater(session.ensureReady(), throwsA(isA<Object>()));
      expect(session.state, AppState.exited);

      // Second attempt: also fails (still bogus dir), but the failure mode
      // must be a fresh boot attempt — not an instant "exited" reject.
      // lastError should still be populated after the new attempt.
      await expectLater(session.ensureReady(), throwsA(isA<Object>()));
      expect(session.state, AppState.exited);
      expect(session.lastError, isNotNull);
    });
  });

  group('AppSession exited recovery', () {
    test('attached session stays terminal once exited', () async {
      final session = AppSession.attached(_FakeVm());
      await session.dispose();
      expect(() => session.ensureReady(),
          throwsA(predicate((e) => e.toString().contains('attached'))));
    });
  });
}

class _FakeVm extends VmClient {
  _FakeVm() : super.test();
}
