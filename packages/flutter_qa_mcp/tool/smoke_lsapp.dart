// Smoke test: boot ls_app companion-production on the iPhone 17 Pro Max
// simulator, attach to the QA isolate, take one snapshot, print a summary.
//
// Usage: dart run tool/smoke_lsapp.dart
//
// This is an ad-hoc verification script (not part of the test suite). It
// reuses FlutterRunner + the in-process tool protocol so we exercise exactly
// the same path an MCP client would.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/runner/flutter_runner.dart';
import 'package:flutter_qa_mcp/src/tools/action_tools.dart';
import 'package:flutter_qa_mcp/src/tools/perception.dart';
import 'package:flutter_qa_mcp/src/tools/sync_tools.dart';
import 'package:flutter_qa_mcp/src/vm/client.dart';

const _project =
    '/Users/mohn93/Desktop/ls_projects/ls_app_development/app/custom/ls_app';
const _deviceId = 'B89DBF36-947C-40D8-8D19-C3644998607E';

Future<void> main() async {
  final runner = FlutterRunner(
    workingDirectory: _project,
    deviceId: _deviceId,
    flutterArgs: const [
      '--flavor', 'companion-production',
      '-t', 'lib/main_companion_production.dart',
    ],
  );
  stderr.writeln('[smoke] booting ls_app companion-production …');
  await runner.start(timeout: const Duration(minutes: 10));
  stderr.writeln('[smoke] VM @ ${runner.vmServiceUri}');

  final vm = await VmClient.connect(runner.vmServiceUri);
  final map = SemanticMap(projectRoot: '/tmp/lsapp_smoke');
  final protocol = McpProtocol(tools: [
    ...perceptionTools(vm, map),
    ...actionTools(vm),
    ...syncTools(vm),
  ]);

  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> a) async {
    final resp = await protocol.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': a},
    });
    if (resp == null || resp['result'] == null) {
      stderr.writeln('[smoke] call("$name") got: ${jsonEncode(resp)}');
      throw StateError('tool $name returned no result');
    }
    final text =
        ((resp['result'] as Map)['content'] as List).first['text'] as String;
    return jsonDecode(text) as Map<String, dynamic>;
  }

  stderr.writeln('[smoke] wait_for_idle …');
  await call('wait_for_idle', {'timeout_ms': 30000});

  // The app shows an iOS native notification permission dialog on first
  // launch. The Flutter probe can't see it (native iOS view, not in widget
  // tree). Pause so you can tap Allow/Don't Allow in the simulator.
  stderr.writeln('');
  stderr.writeln('============================================================');
  stderr.writeln('  ACTION REQUIRED:');
  stderr.writeln('  → If a notification permission dialog is showing in the');
  stderr.writeln('    simulator, tap Allow or Don\'t Allow.');
  stderr.writeln('  → I will sample snapshots for 30s starting now.');
  stderr.writeln('============================================================');
  stderr.writeln('');

  // Sample the app at several points so we can see what's on-screen as
  // it transitions from native splash → first Flutter route.
  for (final waitMs in const [0, 5000, 10000, 15000]) {
    if (waitMs > 0) {
      stderr.writeln('[smoke] sleep ${waitMs}ms then snapshot …');
      await Future.delayed(Duration(milliseconds: waitMs));
    }
    final sw = Stopwatch()..start();
    final snap = await call('snapshot', {});
    sw.stop();

    final elements = (snap['elements'] as List).cast<Map>();
    final unresolved = (snap['unresolved'] as List).cast<Map>();

    stdout.writeln('');
    stdout.writeln('=== snapshot after +${waitMs}ms ===');
    stdout.writeln('latency_ms       : ${sw.elapsedMilliseconds}');
    stdout.writeln('route            : ${snap['route']}');
    stdout.writeln('elements_count   : ${elements.length}');
    stdout.writeln('unresolved_count : ${unresolved.length}');
    stdout.writeln('-- elements --');
    for (final e in elements.take(40)) {
      final label = e['label'] ?? '';
      final role = e['role'] ?? '';
      stdout.writeln('  [${role.toString().padRight(10)}] $label');
    }
    if (elements.length > 40) {
      stdout.writeln('  … and ${elements.length - 40} more');
    }
    if (unresolved.isNotEmpty) {
      stdout.writeln('-- unresolved (first 5) --');
      for (final u in unresolved.take(5)) {
        stdout.writeln(
            '  ${u['widget_type']}  bounds=${u['bounds']}  loc=${u['creation_location']}');
      }
    }
  }

  await vm.dispose();
  await runner.stop();
  exit(0);
}
