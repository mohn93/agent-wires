import 'dart:io';

/// Best-effort reaping of a spawned process and everything it spawned.
///
/// `flutter run --machine` is the visible tip of an iceberg: it forks a DDS
/// (`dart development-service`), and on a physical iPhone a `devicectl`/`script`
/// wrapper plus an `iproxy` USB tunnel. Killing only the flutter PID leaves all
/// of those orphaned to launchd, where they keep contending for the device and
/// VM-service and destabilise the next session (#2).
///
/// The trick is to snapshot the descendant tree *before* killing the root —
/// once the root dies its children reparent to launchd (ppid 1) and a tree
/// walk would no longer find them. We capture them by PID while they're still
/// attached, then signal each one directly.
class ProcessTree {
  /// Parses `ps -A -o pid=,ppid=` output into a `pid -> ppid` map. The `=`
  /// suffixes suppress headers, so every non-blank line is `<pid> <ppid>`.
  /// Malformed lines are skipped rather than throwing — a reaper must never
  /// crash on a weird snapshot.
  static Map<int, int> parsePsTable(String psOutput) {
    final table = <int, int>{};
    for (final line in psOutput.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final pid = int.tryParse(parts[0]);
      final ppid = int.tryParse(parts[1]);
      if (pid == null || ppid == null) continue;
      table[pid] = ppid;
    }
    return table;
  }

  /// All transitive descendants of [root] given a `pid -> ppid` map, excluding
  /// [root] itself. Cycle-safe (a corrupt snapshot can't make it loop).
  static List<int> descendantsOf(int root, Map<int, int> parentOf) {
    final childrenOf = <int, List<int>>{};
    parentOf.forEach((pid, ppid) {
      (childrenOf[ppid] ??= <int>[]).add(pid);
    });
    final result = <int>[];
    final seen = <int>{root};
    final queue = <int>[root];
    while (queue.isNotEmpty) {
      final next = queue.removeLast();
      for (final child in childrenOf[next] ?? const <int>[]) {
        if (!seen.add(child)) continue;
        result.add(child);
        queue.add(child);
      }
    }
    return result;
  }

  /// Kills [rootPid] and its entire descendant tree: SIGTERM first for a clean
  /// shutdown, then SIGKILL after a short grace period for anything that
  /// ignored it. On non-POSIX platforms (no `ps`) it falls back to signalling
  /// just the root. Always best-effort — never throws.
  static Future<void> reap(
    int rootPid, {
    Duration grace = const Duration(milliseconds: 500),
  }) async {
    var descendants = const <int>[];
    if (!Platform.isWindows) {
      try {
        final res = await Process.run('ps', ['-A', '-o', 'pid=,ppid=']);
        if (res.exitCode == 0) {
          descendants = descendantsOf(rootPid, parsePsTable(res.stdout as String));
        }
      } catch (_) {
        // No ps / unexpected failure — degrade to killing just the root.
      }
    }
    final all = [...descendants, rootPid];
    for (final pid in all) {
      _signal(pid, ProcessSignal.sigterm);
    }
    await Future<void>.delayed(grace);
    for (final pid in all) {
      _signal(pid, ProcessSignal.sigkill);
    }
  }

  static void _signal(int pid, ProcessSignal signal) {
    try {
      Process.killPid(pid, signal);
    } catch (_) {
      // Process already gone, or insufficient permission — nothing to do.
    }
  }
}
