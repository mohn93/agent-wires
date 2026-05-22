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
  // tree). Pause 25s so the human can tap Allow/Don't Allow.
  stderr.writeln('');
  stderr.writeln('============================================================');
  stderr.writeln('  ACTION REQUIRED:');
  stderr.writeln('  → If a notification permission dialog is showing in the');
  stderr.writeln('    simulator, tap it now. You have 25 seconds.');
  stderr.writeln('============================================================');
  stderr.writeln('');
  await Future.delayed(const Duration(seconds: 25));
  await call('wait_for_idle', {'timeout_ms': 10000});

  await _driveLogin(call);
  await vm.dispose();
  await runner.stop();
  exit(0);

  // (unused below — kept for ad-hoc multi-sampling)
  // ignore: dead_code
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

typedef _Caller = Future<Map<String, dynamic>> Function(
    String name, Map<String, dynamic> args);

/// Pick the element whose bounds have the largest area among those whose
/// label and role match. device_preview renders the app twice (a small
/// preview thumb + the main frame); the interactive one is the larger.
Map<String, dynamic>? _pickByLabel(
  List<Map<String, dynamic>> elements, {
  required String label,
  String? role,
}) {
  final matches = elements.where((e) {
    if (e['label'] != label) return false;
    if (role != null && e['role'] != role) return false;
    return true;
  }).toList();
  if (matches.isEmpty) return null;
  matches.sort((a, b) {
    final ab = a['bounds'] as Map?;
    final bb = b['bounds'] as Map?;
    final aArea = ((ab?['w'] as num?) ?? 0) * ((ab?['h'] as num?) ?? 0);
    final bArea = ((bb?['w'] as num?) ?? 0) * ((bb?['h'] as num?) ?? 0);
    return (bArea as num).compareTo(aArea as num);
  });
  return matches.first;
}

void _printSnapshot(Map<String, dynamic> snap, {String label = 'snapshot'}) {
  final elements = (snap['elements'] as List).cast<Map>();
  stdout.writeln('');
  stdout.writeln('=== $label ===');
  stdout.writeln('route          : ${snap['route']}');
  stdout.writeln('elements_count : ${elements.length}');
  for (final e in elements.take(40)) {
    final lbl = e['label'] ?? '';
    final role = e['role'] ?? '';
    final b = e['bounds'] as Map?;
    final bounds = b == null
        ? '?'
        : '${(b['x'] as num).toStringAsFixed(0)},${(b['y'] as num).toStringAsFixed(0)} '
            '${(b['w'] as num).toStringAsFixed(0)}x${(b['h'] as num).toStringAsFixed(0)}';
    stdout.writeln(
        '  [${role.toString().padRight(10)}] ${lbl.toString().padRight(30)}  $bounds');
  }
}

Future<void> _driveLogin(_Caller call) async {
  // Real credentials passed in by the user for this smoke run. Inlined
  // here for the single run; the script is meant to be discarded after.
  const email = 'mohn93@gmail.com';
  const password = 'Lahloh.1310';

  stderr.writeln('[smoke] snapshot BEFORE login …');
  final pre = await call('snapshot', {});
  _printSnapshot(pre, label: 'BEFORE login');
  final elements =
      (pre['elements'] as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();

  final emailField = _pickByLabel(elements, label: 'Email', role: 'textfield');
  final passField =
      _pickByLabel(elements, label: 'Password', role: 'textfield');
  final signInBtn = _pickByLabel(elements, label: 'Sign in', role: 'button');

  if (emailField == null || passField == null || signInBtn == null) {
    stderr.writeln(
        '[smoke] BLOCKED: missing field — email=$emailField pass=$passField signIn=$signInBtn');
    try {
      final res = await Process.run('xcrun',
          ['simctl', 'io', 'booted', 'screenshot', '/tmp/lsapp_blocked.png']);
      stderr.writeln('[smoke] /tmp/lsapp_blocked.png rc=${res.exitCode}');
    } catch (_) {}
    return;
  }
  stderr.writeln('[smoke] using email=${emailField['id']} pass=${passField['id']} signIn=${signInBtn['id']}');

  stderr.writeln('[smoke] enter Email …');
  final r1 = await call('enter_text', {
    'element_id': emailField['id'],
    'text': email,
  });
  stderr.writeln('  → ${jsonEncode(r1)}');

  stderr.writeln('[smoke] enter Password …');
  final r2 = await call('enter_text', {
    'element_id': passField['id'],
    'text': password,
  });
  stderr.writeln('  → ${jsonEncode(r2)}');

  stderr.writeln('[smoke] snapshot after typing …');
  _printSnapshot(await call('snapshot', {}), label: 'AFTER typing');

  stderr.writeln('[smoke] tap Sign in …');
  final r3 = await call('tap', {'element_id': signInBtn['id']});
  stderr.writeln('  → ${jsonEncode(r3)}');

  // Auth hits the network; wait_for_idle waits for HTTP/timers to settle.
  stderr.writeln('[smoke] wait_for_idle 25s …');
  await call('wait_for_idle', {'timeout_ms': 25000});
  await Future.delayed(const Duration(seconds: 3));

  _printSnapshot(await call('snapshot', {}), label: 'AFTER tap Sign in');

  // Native simctl screenshot so we can see what actually rendered.
  try {
    final res = await Process.run(
        'xcrun', ['simctl', 'io', 'booted', 'screenshot', '/tmp/lsapp_after_login.png']);
    stderr.writeln('[smoke] native screenshot rc=${res.exitCode}');
  } catch (e) {
    stderr.writeln('[smoke] native screenshot failed: $e');
  }
}
