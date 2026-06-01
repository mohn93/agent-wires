import 'package:agent_wires_mcp/src/runner/flutter_runner.dart';
import 'package:test/test.dart';

void main() {
  group('isDevFsSyncFailure (#5)', () {
    test('matches the flutter "DevFS synchronization failed" payload', () {
      expect(
          isDevFsSyncFailure(
              {'code': 1, 'message': 'DevFS synchronization failed'}),
          isTrue);
    });

    test('is case-insensitive', () {
      expect(
          isDevFsSyncFailure(
              {'code': 1, 'message': 'devfs synchronization FAILED'}),
          isTrue);
    });

    test('a success (code 0) is never a DevFS failure', () {
      expect(
          isDevFsSyncFailure(
              {'code': 0, 'message': 'DevFS synchronization failed'}),
          isFalse);
    });

    test('an unrelated failure is not a DevFS failure', () {
      expect(isDevFsSyncFailure({'code': 1, 'message': 'compile error'}),
          isFalse);
    });
  });

  group('hot reload/restart DevFS retry (#5)', () {
    test('retries once after a DevFS sync failure and recovers', () async {
      final runner = _ScriptedRunner([
        {'code': 1, 'message': 'DevFS synchronization failed'},
        {'code': 0},
      ]);
      final res = await runner.hotReload();
      expect(runner.calls, 2, reason: 'one retry');
      expect(res['code'], 0);
      expect(res['recoverable'], isNull, reason: 'recovered — no hint');
    });

    test('a persistent DevFS failure surfaces an explicit recovery hint',
        () async {
      final runner = _ScriptedRunner([
        {'code': 1, 'message': 'DevFS synchronization failed'},
        {'code': 1, 'message': 'DevFS synchronization failed'},
      ]);
      final res = await runner.hotReload();
      expect(runner.calls, 2, reason: 'retry once, not forever');
      expect(res['recoverable'], isFalse);
      expect((res['hint'] as String).toLowerCase(), contains('boot_app'));
    });

    test('a successful reload is not retried', () async {
      final runner = _ScriptedRunner([
        {'code': 0}
      ]);
      await runner.hotReload();
      expect(runner.calls, 1);
    });

    test('a non-DevFS failure is returned as-is, no retry, no hint', () async {
      final runner = _ScriptedRunner([
        {'code': 1, 'message': 'compile error: missing ;'}
      ]);
      final res = await runner.hotReload();
      expect(runner.calls, 1);
      expect(res['recoverable'], isNull);
      expect(res['code'], 1);
    });
  });
}

/// Returns canned restart responses in order instead of talking to a real
/// flutter subprocess, so the retry orchestration is testable.
class _ScriptedRunner extends FlutterRunner {
  _ScriptedRunner(this._responses) : super(workingDirectory: '/tmp');
  final List<Map<String, dynamic>> _responses;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> sendRestart({
    required bool fullRestart,
    required Duration timeout,
  }) async =>
      _responses[calls++];
}
