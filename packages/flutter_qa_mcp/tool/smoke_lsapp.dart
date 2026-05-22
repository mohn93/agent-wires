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
  await runner.start(timeout: const Duration(minutes: 20));
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

/// Pick the element that's actually visible. device_preview clones the
/// widget tree, so each interactive widget appears twice — once at the
/// real viewport coordinates and once shifted off-screen by the preview
/// frame's transform. The "largest area" heuristic fails when both copies
/// have the same area; switch to "must be inside the viewport".
Map<String, dynamic>? _pickByLabel(
  List<Map<String, dynamic>> elements, {
  required String label,
  String? role,
  required double viewportW,
  required double viewportH,
}) {
  final matches = elements.where((e) {
    if (e['label'] != label) return false;
    if (role != null && e['role'] != role) return false;
    return true;
  }).toList();
  if (matches.isEmpty) return null;

  // Visible = bounding rect lies (mostly) inside [0..viewportW] × [0..viewportH].
  // Allow a few pixels of slack for shadows/over-render.
  const slack = 8.0;
  bool isVisible(Map<String, dynamic> e) {
    final b = e['bounds'] as Map?;
    if (b == null) return false;
    final x = (b['x'] as num).toDouble();
    final y = (b['y'] as num).toDouble();
    final w = (b['w'] as num).toDouble();
    final h = (b['h'] as num).toDouble();
    return x >= -slack &&
        y >= -slack &&
        (x + w) <= viewportW + slack &&
        (y + h) <= viewportH + slack;
  }

  final visible = matches.where(isVisible).toList();
  final pool = visible.isNotEmpty ? visible : matches;
  pool.sort((a, b) {
    final ab = a['bounds'] as Map?;
    final bb = b['bounds'] as Map?;
    final aArea = ((ab?['w'] as num?) ?? 0) * ((ab?['h'] as num?) ?? 0);
    final bArea = ((bb?['w'] as num?) ?? 0) * ((bb?['h'] as num?) ?? 0);
    return (bArea as num).compareTo(aArea as num);
  });
  return pool.first;
}

({double w, double h}) _viewport(Map<String, dynamic> snap) {
  final v = snap['viewport'] as Map?;
  return (
    w: ((v?['w'] as num?) ?? 440).toDouble(),
    h: ((v?['h'] as num?) ?? 956).toDouble(),
  );
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

  // The app persists auth between launches. If we're already past the
  // login route, skip everything and jump straight to explore.
  final route = pre['route'] as String?;
  if (route == 'MainRoute') {
    stderr.writeln('[smoke] already logged in (route=MainRoute), skipping auth');
    await _exploreLoop(call);
    return;
  }

  final elements =
      (pre['elements'] as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
  final vp = _viewport(pre);

  final emailField = _pickByLabel(elements,
      label: 'Email', role: 'textfield', viewportW: vp.w, viewportH: vp.h);
  final passField = _pickByLabel(elements,
      label: 'Password', role: 'textfield', viewportW: vp.w, viewportH: vp.h);
  final signInBtn = _pickByLabel(elements,
      label: 'Sign in', role: 'button', viewportW: vp.w, viewportH: vp.h);

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

  await _shot('/tmp/lsapp_after_login.png');

  // === Phase 2: pick "Mohanned Benmesken" → Continue → OTP screen ===
  await _pickAccountAndContinue(call);
}

Future<void> _pickAccountAndContinue(_Caller call) async {
  await call('wait_for_idle', {'timeout_ms': 8000});

  final snap1 = await call('snapshot', {});
  final list1 = (snap1['elements'] as List).cast<Map>().map(_asDyn).toList();
  final vp1 = _viewport(snap1);
  final mohanned = _pickByLabel(list1,
      label: 'Mohanned Benmesken',
      role: 'list_item',
      viewportW: vp1.w,
      viewportH: vp1.h);
  if (mohanned == null) {
    stderr.writeln('[smoke] BLOCKED: no Mohanned Benmesken list_item');
    await _shot('/tmp/lsapp_blocked.png');
    return;
  }
  stderr.writeln('[smoke] tap account "Mohanned Benmesken" (${mohanned['id']}) …');
  final tapRes = await call('tap', {'element_id': mohanned['id']});
  stderr.writeln('  → ${jsonEncode(tapRes)}');

  await call('wait_for_idle', {'timeout_ms': 5000});
  await Future.delayed(const Duration(seconds: 1));

  // After picking the account, the Continue button should be enabled.
  final snap2 = await call('snapshot', {});
  _printSnapshot(snap2, label: 'AFTER pick Mohanned');
  final list2 = (snap2['elements'] as List).cast<Map>().map(_asDyn).toList();
  final vp2 = _viewport(snap2);
  final cont = _pickByLabel(list2,
      label: 'Continue',
      role: 'button',
      viewportW: vp2.w,
      viewportH: vp2.h);
  if (cont == null) {
    stderr.writeln('[smoke] BLOCKED: no Continue button');
    await _shot('/tmp/lsapp_blocked.png');
    return;
  }
  stderr.writeln('[smoke] tap Continue (${cont['id']}) …');
  final r = await call('tap', {'element_id': cont['id']});
  stderr.writeln('  → ${jsonEncode(r)}');

  // Continue triggers the OTP send (network). Give it time to navigate.
  await call('wait_for_idle', {'timeout_ms': 25000});
  await Future.delayed(const Duration(seconds: 3));

  final snap3 = await call('snapshot', {});
  _printSnapshot(snap3, label: 'OTP screen');
  await _shot('/tmp/lsapp_otp_screen.png');

  // === Phase 3: wait for OTP via /tmp/lsapp_otp.txt ===
  stderr.writeln('');
  stderr.writeln('============================================================');
  stderr.writeln('  Waiting for OTP. Drop the 4–6 digit code into:');
  stderr.writeln('  /tmp/lsapp_otp.txt');
  stderr.writeln('  (the controller will write it for you).');
  stderr.writeln('  Polling for up to 5 minutes.');
  stderr.writeln('============================================================');
  final otp = await _readOtpFromFile(
      const Duration(minutes: 5), '/tmp/lsapp_otp.txt');
  if (otp == null) {
    stderr.writeln('[smoke] no OTP received in time, exiting');
    return;
  }
  stderr.writeln('[smoke] got OTP (${otp.length} digits)');

  await _enterOtpAndSubmit(call, otp);
}

Future<String?> _readOtpFromFile(Duration timeout, String path) async {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      final raw = file.readAsStringSync().trim();
      if (raw.isNotEmpty) {
        final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleaned.length >= 4) return cleaned;
      }
    }
    await Future.delayed(const Duration(seconds: 2));
  }
  return null;
}

Future<void> _enterOtpAndSubmit(_Caller call, String otp) async {
  final snap = await call('snapshot', {});
  _printSnapshot(snap, label: 'OTP screen before typing');
  // Hidden OTP text inputs (pin_code_fields style — fontSize:0.01, transparent)
  // have no visible text, so they land in unresolved[], not elements[]. Merge.
  final elements = [
    ...(snap['elements'] as List).cast<Map>().map(_asDyn),
    ...(snap['unresolved'] as List).cast<Map>().map(_asDyn),
  ];
  stderr.writeln(
      '[smoke] merged elements (${(snap['elements'] as List).length}) + '
      'unresolved (${(snap['unresolved'] as List).length}) = ${elements.length}');
  final vp = _viewport(snap);

  // OTP UIs come in two flavors: one wide textfield, or N single-digit
  // textfields side-by-side. Detect by counting textfields with small
  // adjacent bounds.
  //
  // device_preview clones every textfield off-screen; only keep the
  // ones whose bounds sit inside the viewport.
  bool inViewport(Map e) {
    final b = e['bounds'] as Map?;
    if (b == null) return false;
    final x = (b['x'] as num).toDouble();
    final y = (b['y'] as num).toDouble();
    final w = (b['w'] as num).toDouble();
    final h = (b['h'] as num).toDouble();
    return x >= -8 && y >= -8 && x + w <= vp.w + 8 && y + h <= vp.h + 8;
  }

  final textfields = elements
      .where((e) => e['role'] == 'textfield' && inViewport(e))
      .toList();
  stderr.writeln('[smoke] found ${textfields.length} textfields');

  if (textfields.isEmpty) {
    stderr.writeln('[smoke] BLOCKED: no textfield on OTP screen');
    await _shot('/tmp/lsapp_blocked.png');
    return;
  }

  // Heuristic: if there's a textfield whose width > 100, treat it as a
  // single OTP input. Otherwise assume N single-digit fields ordered by x.
  final wide = textfields.where((e) {
    final b = e['bounds'] as Map?;
    return ((b?['w'] as num?) ?? 0) > 100;
  }).toList();

  if (wide.isNotEmpty) {
    final field = _pickLargest(wide);
    stderr.writeln('[smoke] enter_text into single OTP field (${field['id']}) …');
    final r = await call('enter_text', {
      'element_id': field['id'],
      'text': otp,
    });
    stderr.writeln('  → ${jsonEncode(r)}');
  } else {
    // Multiple single-digit fields. Sort by x ascending, type one char each.
    final boxes = textfields
        .where((e) => e['bounds'] != null)
        .toList()
      ..sort((a, b) {
        final ax = (a['bounds'] as Map)['x'] as num;
        final bx = (b['bounds'] as Map)['x'] as num;
        return ax.compareTo(bx);
      });
    for (var i = 0; i < otp.length && i < boxes.length; i++) {
      final field = boxes[i] as Map<String, dynamic>;
      stderr.writeln('[smoke] digit ${i + 1}/${otp.length} → ${field['id']} …');
      await call('enter_text', {
        'element_id': field['id'],
        'text': otp[i],
      });
    }
  }

  await call('wait_for_idle', {'timeout_ms': 8000});
  await Future.delayed(const Duration(seconds: 2));

  // Find and tap any obvious submit button.
  final post = await call('snapshot', {});
  final postElems =
      (post['elements'] as List).cast<Map>().map(_asDyn).toList();
  final vpPost = _viewport(post);
  Map<String, dynamic>? submit;
  for (final lbl in ['Verify', 'Confirm', 'Continue', 'Submit', 'Sign in']) {
    submit = _pickByLabel(postElems,
        label: lbl, role: 'button', viewportW: vpPost.w, viewportH: vpPost.h);
    if (submit != null) {
      stderr.writeln('[smoke] tapping submit button "$lbl" (${submit['id']}) …');
      final r = await call('tap', {'element_id': submit['id']});
      stderr.writeln('  → ${jsonEncode(r)}');
      break;
    }
  }
  if (submit == null) {
    stderr.writeln('[smoke] no obvious submit button; OTP may auto-submit on entry');
  }

  await call('wait_for_idle', {'timeout_ms': 30000});
  await Future.delayed(const Duration(seconds: 4));
  _printSnapshot(await call('snapshot', {}), label: 'AFTER OTP submit');
  await _shot('/tmp/lsapp_after_otp.png');

  await _exploreLoop(call);
}

/// Polls /tmp/lsapp_cmd.txt for commands. The controller (me) writes one
/// command line at a time; the smoke reads, executes, deletes the file,
/// snapshots, and screenshots. Output goes to the log and indexed PNGs.
///
/// Commands:
///   snapshot                 — re-snapshot and print
///   shot                     — take a native screenshot only
///   tap <label substring>    — find by label (case-insensitive contains),
///                              largest in-viewport, tap
///   tap_id <e_N>             — tap by element_id
///   back                     — press_back
///   wait <ms>                — wait_for_idle then sleep
///   scroll <up|down>         — scroll a viewport-sized swipe
///   text <e_N>=<value>       — enter_text into element id
///   quit                     — exit cleanly
Future<void> _exploreLoop(_Caller call) async {
  const cmdPath = '/tmp/lsapp_cmd.txt';
  const statePath = '/tmp/lsapp_state.json';
  var step = 0;

  Future<void> takeAndDump(String tag) async {
    final snap = await call('snapshot', {});
    final vp = _viewport(snap);
    final merged = [
      ...(snap['elements'] as List).cast<Map>().map(_asDyn),
      ...(snap['unresolved'] as List).cast<Map>().map(_asDyn),
    ];
    // Drop the off-screen device_preview clones from the printed report.
    bool inViewport(Map<String, dynamic> e) {
      final b = e['bounds'] as Map?;
      if (b == null) return false;
      final x = (b['x'] as num).toDouble();
      final y = (b['y'] as num).toDouble();
      final w = (b['w'] as num).toDouble();
      final h = (b['h'] as num).toDouble();
      return x >= -8 && y >= -8 && x + w <= vp.w + 8 && y + h <= vp.h + 8;
    }
    final visible = merged.where(inViewport).toList();
    File(statePath).writeAsStringSync(jsonEncode({
      'tag': tag,
      'step': step,
      'route': snap['route'],
      'visible': visible,
    }));
    stdout.writeln('');
    stdout.writeln('=== step $step: $tag ===');
    stdout.writeln('route          : ${snap['route']}');
    stdout.writeln('visible_count  : ${visible.length}');
    for (final e in visible) {
      final lbl = e['label'] ?? '';
      final role = e['role'] ?? '';
      final id = e['id'];
      final b = e['bounds'] as Map?;
      final bounds = b == null
          ? '?'
          : '${(b['x'] as num).toStringAsFixed(0)},${(b['y'] as num).toStringAsFixed(0)} '
              '${(b['w'] as num).toStringAsFixed(0)}x${(b['h'] as num).toStringAsFixed(0)}';
      stdout.writeln(
          '  $id  [${role.toString().padRight(10)}] ${lbl.toString().padRight(28)}  $bounds');
    }
    await _shot('/tmp/lsapp_explore_${step.toString().padLeft(3, '0')}.png');
  }

  stdout.writeln('');
  stdout.writeln('============================================================');
  stdout.writeln('  EXPLORE MODE — drop commands into $cmdPath');
  stdout.writeln('============================================================');

  await takeAndDump('explore-start');

  while (true) {
    final f = File(cmdPath);
    while (!f.existsSync()) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    final raw = f.readAsStringSync().trim();
    try { f.deleteSync(); } catch (_) {}
    if (raw.isEmpty) continue;
    step++;
    stdout.writeln('');
    stdout.writeln('>>> step $step cmd: $raw');

    final parts = raw.split(' ');
    final verb = parts.first.toLowerCase();
    final rest = parts.skip(1).join(' ');

    try {
      switch (verb) {
        case 'snapshot':
          await call('wait_for_idle', {'timeout_ms': 5000});
          await takeAndDump('snapshot');
          break;
        case 'shot':
          await _shot('/tmp/lsapp_explore_${step.toString().padLeft(3, '0')}.png');
          stdout.writeln('  shot taken');
          break;
        case 'tap':
          await _exploreTap(call, label: rest);
          await Future.delayed(const Duration(milliseconds: 800));
          await call('wait_for_idle', {'timeout_ms': 8000});
          await Future.delayed(const Duration(seconds: 1));
          await takeAndDump('after tap "$rest"');
          break;
        case 'tap_id':
          final r = await call('tap', {'element_id': rest});
          stdout.writeln('  → ${jsonEncode(r)}');
          await call('wait_for_idle', {'timeout_ms': 8000});
          await Future.delayed(const Duration(seconds: 1));
          await takeAndDump('after tap_id $rest');
          break;
        case 'back':
          final r = await call('press_back', {});
          stdout.writeln('  → ${jsonEncode(r)}');
          await call('wait_for_idle', {'timeout_ms': 5000});
          await Future.delayed(const Duration(milliseconds: 800));
          await takeAndDump('after back');
          break;
        case 'wait':
          final ms = int.tryParse(rest) ?? 3000;
          await call('wait_for_idle', {'timeout_ms': ms});
          await takeAndDump('after wait ${ms}ms');
          break;
        case 'scroll':
          await _exploreScroll(call, direction: rest);
          await Future.delayed(const Duration(milliseconds: 500));
          await takeAndDump('after scroll $rest');
          break;
        case 'text':
          final eq = rest.indexOf('=');
          if (eq < 0) {
            stdout.writeln('  bad text cmd, want "e_N=value"');
            break;
          }
          final id = rest.substring(0, eq).trim();
          final value = rest.substring(eq + 1);
          final r = await call(
              'enter_text', {'element_id': id, 'text': value});
          stdout.writeln('  → ${jsonEncode(r)}');
          await call('wait_for_idle', {'timeout_ms': 4000});
          await takeAndDump('after text $id');
          break;
        case 'quit':
          stdout.writeln('  bye');
          return;
        default:
          stdout.writeln('  unknown verb: $verb');
      }
    } catch (e, st) {
      stdout.writeln('  ERROR: $e');
      stdout.writeln(st);
    }
  }
}

Future<void> _exploreTap(_Caller call,
    {required String label}) async {
  final snap = await call('snapshot', {});
  final vp = _viewport(snap);
  final merged = [
    ...(snap['elements'] as List).cast<Map>().map(_asDyn),
    ...(snap['unresolved'] as List).cast<Map>().map(_asDyn),
  ];
  bool inViewport(Map<String, dynamic> e) {
    final b = e['bounds'] as Map?;
    if (b == null) return false;
    final x = (b['x'] as num).toDouble();
    final y = (b['y'] as num).toDouble();
    final w = (b['w'] as num).toDouble();
    final h = (b['h'] as num).toDouble();
    return x >= -8 && y >= -8 && x + w <= vp.w + 8 && y + h <= vp.h + 8;
  }
  final needle = label.toLowerCase();
  final matches = merged.where((e) {
    final lbl = (e['label'] as String?)?.toLowerCase();
    if (lbl == null) return false;
    return lbl.contains(needle) && inViewport(e);
  }).toList();
  if (matches.isEmpty) {
    stdout.writeln('  no visible element matches "$label"');
    return;
  }
  // Smallest area wins — more specific target.
  matches.sort((a, b) {
    final ab = a['bounds'] as Map;
    final bb = b['bounds'] as Map;
    final aArea = (ab['w'] as num) * (ab['h'] as num);
    final bArea = (bb['w'] as num) * (bb['h'] as num);
    return aArea.compareTo(bArea);
  });
  final pick = matches.first;
  stdout.writeln(
      '  matched ${matches.length}; tapping ${pick['id']} "${pick['label']}"');
  final r = await call('tap', {'element_id': pick['id']});
  stdout.writeln('  → ${jsonEncode(r)}');
}

Future<void> _exploreScroll(_Caller call,
    {required String direction}) async {
  final dir = direction.trim().toLowerCase();
  final r = await call('scroll', {
    'direction': (dir == 'up' || dir == 'down') ? dir : 'down',
    'distance': 400,
  });
  stdout.writeln('  → ${jsonEncode(r)}');
}

Map<String, dynamic> _asDyn(Map e) => e.cast<String, dynamic>();
Map<String, dynamic> _pickLargest(List<Map<String, dynamic>> xs) {
  xs.sort((a, b) {
    final ab = a['bounds'] as Map;
    final bb = b['bounds'] as Map;
    final aArea = (ab['w'] as num) * (ab['h'] as num);
    final bArea = (bb['w'] as num) * (bb['h'] as num);
    return bArea.compareTo(aArea);
  });
  return xs.first;
}

Future<void> _shot(String path) async {
  try {
    final res = await Process.run(
        'xcrun', ['simctl', 'io', 'booted', 'screenshot', path]);
    stderr.writeln('[smoke] $path rc=${res.exitCode}');
  } catch (e) {
    stderr.writeln('[smoke] shot $path failed: $e');
  }
}
