import 'package:agent_wires_mcp/src/runner/flutter_runner.dart';
import 'package:test/test.dart';

void main() {
  group('extractProgressMessage', () {
    test('app.progress event with a message returns the message', () {
      expect(
        extractProgressMessage('app.progress', {
          'id': '1',
          'progressId': 'launch',
          'message': 'Running Xcode build...',
        }),
        'Running Xcode build...',
      );
    });

    test('non-error daemon.logMessage is surfaced (truncated past 200 chars)',
        () {
      final long = List.filled(300, 'a').join();
      final out = extractProgressMessage(
        'daemon.logMessage',
        {'level': 'info', 'message': long},
      );
      expect(out, isNotNull);
      expect(out!.length, 200);
      expect(out.endsWith('...'), isTrue);
    });

    test('error-level daemon.logMessage is NOT a progress message', () {
      expect(
        extractProgressMessage(
          'daemon.logMessage',
          {'level': 'error', 'message': 'Build failed'},
        ),
        isNull,
      );
    });

    test('unrelated events are ignored', () {
      expect(
        extractProgressMessage('app.started', {'appId': 'x'}),
        isNull,
      );
    });
  });

  group('extractLaunchFailure', () {
    test('app.stop with error returns the error string', () {
      expect(
        extractLaunchFailure(
          'app.stop',
          {'appId': 'x', 'error': 'No supported devices connected'},
        ),
        'No supported devices connected',
      );
    });

    test('app.stop with no error returns null (clean shutdown)', () {
      expect(extractLaunchFailure('app.stop', {'appId': 'x'}), isNull);
    });

    test('error-level daemon.logMessage is a launch failure', () {
      expect(
        extractLaunchFailure(
          'daemon.logMessage',
          {'level': 'error', 'message': 'Gradle build failed'},
        ),
        'Gradle build failed',
      );
    });

    test('info-level daemon.logMessage is NOT a launch failure', () {
      expect(
        extractLaunchFailure(
          'daemon.logMessage',
          {'level': 'info', 'message': 'Compiling...'},
        ),
        isNull,
      );
    });
  });
}
