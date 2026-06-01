import 'package:agent_wires_mcp/src/runner/flutter_runner.dart';
import 'package:test/test.dart';

void main() {
  test('start fails fast when the flutter process exits before a VM URI',
      () async {
    // `false` exits non-zero immediately — modelling `flutter run` dying on a
    // build/codesign/SDK failure (or `flutter` resolving to the wrong, e.g.
    // fvm-managed, SDK) before it ever emits a VM service URI. start() must
    // surface that promptly instead of waiting out the minutes-long timeout —
    // the boot-hang where app_status sits on a stale "Running Xcode build..."
    // while no flutter/xcodebuild process is even alive.
    final runner = FlutterRunner(workingDirectory: '/tmp', executable: 'false');
    final sw = Stopwatch()..start();
    await expectLater(
      runner.start(timeout: const Duration(seconds: 30)),
      throwsA(predicate(
          (e) => e.toString().toLowerCase().contains('exited'))),
    );
    sw.stop();
    expect(sw.elapsed.inSeconds, lessThan(5),
        reason: 'must fail on process exit, not wait out the timeout');
  }, testOn: 'posix');
}
