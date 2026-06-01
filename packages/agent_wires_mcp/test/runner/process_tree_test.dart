import 'dart:io';

import 'package:agent_wires_mcp/src/runner/process_tree.dart';
import 'package:test/test.dart';

void main() {
  group('parsePsTable', () {
    test('parses `ps -A -o pid=,ppid=` output into a pid->ppid map', () {
      const out = '''
    1     0
  340     1
  512   340
  998   512
''';
      final table = ProcessTree.parsePsTable(out);
      expect(table[340], 1);
      expect(table[512], 340);
      expect(table[998], 512);
      expect(table.containsKey(1), isTrue);
    });

    test('ignores blank and malformed lines', () {
      const out = '\n  100   1\ngarbage line\n  200 abc\n  201   100\n';
      final table = ProcessTree.parsePsTable(out);
      expect(table, {100: 1, 201: 100});
    });
  });

  group('descendantsOf', () {
    test('returns the full transitive child set, excluding the root', () {
      // 340 -> 512 -> 998, and 340 -> 777. Root 340 owns {512, 998, 777}.
      final parentOf = {1: 0, 340: 1, 512: 340, 998: 512, 777: 340, 50: 1};
      final desc = ProcessTree.descendantsOf(340, parentOf);
      expect(desc.toSet(), {512, 998, 777});
      expect(desc, isNot(contains(340)), reason: 'root is not its own child');
      expect(desc, isNot(contains(50)), reason: 'unrelated pid excluded');
    });

    test('returns empty for a leaf pid', () {
      final parentOf = {1: 0, 340: 1, 512: 340};
      expect(ProcessTree.descendantsOf(512, parentOf), isEmpty);
    });

    test('does not loop on a cyclic table', () {
      // Defensive: a corrupt snapshot must not hang the reaper.
      final parentOf = {10: 11, 11: 10};
      final desc = ProcessTree.descendantsOf(10, parentOf);
      expect(desc, isNot(contains(10)));
    });
  });

  group('reap (real processes)', () {
    test('kills the root AND its orphan-prone child subprocess', () async {
      // A shell that spawns a background `sleep` and prints its pid: the exact
      // shape of `flutter run` spawning DDS/iproxy. Reaping the shell must
      // take the child with it (#2) — not leave it orphaned to launchd.
      final proc = await Process.start(
        'sh',
        ['-c', 'sleep 60 & echo \$!; wait'],
      );
      final childPid = int.parse(
        (await proc.stdout
                .transform(const SystemEncoding().decoder)
                .first)
            .trim(),
      );

      await ProcessTree.reap(proc.pid);

      // signal 0 probes existence without killing; false => already reaped.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(Process.killPid(proc.pid, ProcessSignal.sigterm), isFalse,
          reason: 'root must be gone');
      expect(Process.killPid(childPid, ProcessSignal.sigterm), isFalse,
          reason: 'orphan-prone child must be gone too');
    }, testOn: 'posix');
  });
}
