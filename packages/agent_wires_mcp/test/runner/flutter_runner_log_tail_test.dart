import 'dart:io';

import 'package:agent_wires_mcp/src/runner/flutter_runner.dart';
import 'package:test/test.dart';

void main() {
  test('a premature exit quotes the recent stdout log, not just stderr',
      () async {
    // `flutter run --machine` reports Xcode's build output as status-level
    // daemon.logMessage events on STDOUT; only the generic "Could not build
    // the application for the simulator" lands on stderr. The boot error
    // must include the stdout tail so the agent sees the actual failure.
    final script = File('${Directory.systemTemp.path}/fake_flutter_$pid.sh');
    script.writeAsStringSync('''#!/bin/sh
echo '[{"event":"daemon.logMessage","params":{"level":"status","message":"Xcode build done. 12.3s"}}]'
echo '[{"event":"daemon.logMessage","params":{"level":"status","message":"Xcode output: error: Sandbox: rsync.samba(1234) deny(1) file-write-create"}}]'
echo 'Could not build the application for the simulator.' 1>&2
exit 1
''');
    await Process.run('chmod', ['+x', script.path]);
    addTearDown(() => script.deleteSync());

    final runner =
        FlutterRunner(workingDirectory: '/tmp', executable: script.path);
    await expectLater(
      runner.start(timeout: const Duration(seconds: 30)),
      throwsA(predicate((e) {
        final s = e.toString();
        return s.contains('rsync.samba') && s.contains('Could not build');
      })),
    );
  }, testOn: 'posix');
}
