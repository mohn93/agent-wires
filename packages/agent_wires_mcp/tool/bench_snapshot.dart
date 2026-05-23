// Snapshot-latency benchmark. Boots demo_app on the given device, navigates
// through home + cart + stress, and times N back-to-back snapshot calls per
// screen. Prints per-screen min/p50/p99/max in milliseconds.
//
// Usage: dart run tool/bench_snapshot.dart [-d <device-id>] [--iters N]

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:agent_wires_mcp/src/map/semantic_map.dart';
import 'package:agent_wires_mcp/src/mcp/protocol.dart';
import 'package:agent_wires_mcp/src/runner/flutter_runner.dart';
import 'package:agent_wires_mcp/src/tools/action_tools.dart';
import 'package:agent_wires_mcp/src/tools/perception.dart';
import 'package:agent_wires_mcp/src/tools/sync_tools.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('device', abbr: 'd', help: 'Device id (default: \$FLUTTER_QA_E2E_DEVICE or flutter\'s pick)')
    ..addOption('iters', defaultsTo: '20', help: 'Snapshot calls per screen')
    ..addOption('project', defaultsTo: '../../examples/demo_app');
  final parsed = parser.parse(args);
  final iters = int.parse(parsed['iters'] as String);
  final device =
      (parsed['device'] as String?) ?? Platform.environment['FLUTTER_QA_E2E_DEVICE'];

  final runner = FlutterRunner(
    workingDirectory: parsed['project'] as String,
    deviceId: device,
  );
  stderr.writeln('Booting Flutter app …');
  await runner.start();
  stderr.writeln('VM @ ${runner.vmServiceUri}');

  final vm = await VmClient.connect(runner.vmServiceUri);
  final map = SemanticMap(projectRoot: '/tmp');
  final protocol = McpProtocol(tools: [
    ...perceptionTools(vm, map),
    ...actionTools(vm),
    ...syncTools(vm),
  ]);
  Future<Map<String, dynamic>> callTool(
      String name, Map<String, dynamic> args) async {
    final resp = await protocol.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': args},
    });
    final text =
        ((resp!['result'] as Map)['content'] as List).first['text'] as String;
    return jsonDecode(text) as Map<String, dynamic>;
  }

  // Let first frame paint.
  await callTool('wait_for_idle', {'timeout_ms': 10000});

  final results = <String, BenchResult>{};
  Future<void> measure(String screen, {Future<void> Function()? before}) async {
    if (before != null) await before();
    await callTool('wait_for_idle', {'timeout_ms': 5000});
    final samples = <int>[];
    final beforeSnap = await callTool('snapshot', {});
    final elementCount = (beforeSnap['elements'] as List).length +
        (beforeSnap['unresolved'] as List).length;
    for (var i = 0; i < iters; i++) {
      final sw = Stopwatch()..start();
      await callTool('snapshot', {});
      sw.stop();
      samples.add(sw.elapsedMilliseconds);
    }
    results[screen] = BenchResult(
      screen: screen,
      elementCount: elementCount,
      samplesMs: samples,
    );
  }

  await measure('home');

  // Navigate to /cart via the existing labelled button.
  await measure('cart', before: () async {
    final snap = await callTool('snapshot', {});
    final cart = (snap['elements'] as List).firstWhere(
      (e) => (e as Map)['label'] == 'Go to cart',
    ) as Map;
    await callTool('tap', {'element_id': cart['id']});
    await callTool('wait_for_route', {'route': '/cart', 'timeout_ms': 5000});
  });

  // Pop back, then push the stress screen.
  await measure('stress', before: () async {
    await callTool('press_back', {});
    await callTool('wait_for_route', {'route': '/', 'timeout_ms': 5000});
    final snap = await callTool('snapshot', {});
    final stress = (snap['elements'] as List).firstWhere(
      (e) => (e as Map)['label'] == 'Stress test',
    ) as Map;
    await callTool('tap', {'element_id': stress['id']});
    await callTool('wait_for_route', {'route': '/stress', 'timeout_ms': 5000});
  });

  stdout.writeln('');
  stdout.writeln('Snapshot latency (ms), iters=$iters:');
  stdout.writeln(
      '  ${'screen'.padRight(8)}  ${'elems'.padLeft(5)}  ${'min'.padLeft(6)}  ${'p50'.padLeft(6)}  ${'p99'.padLeft(6)}  ${'max'.padLeft(6)}  ${'mean'.padLeft(6)}');
  for (final r in results.values) {
    stdout.writeln(r.format());
  }

  await vm.dispose();
  await runner.stop();
  exit(0);
}

class BenchResult {
  BenchResult({
    required this.screen,
    required this.elementCount,
    required this.samplesMs,
  });
  final String screen;
  final int elementCount;
  final List<int> samplesMs;

  String format() {
    final sorted = [...samplesMs]..sort();
    final min = sorted.first;
    final max = sorted.last;
    final p50 = sorted[sorted.length ~/ 2];
    final p99 = sorted[((sorted.length - 1) * 0.99).floor()];
    final mean = (sorted.reduce((a, b) => a + b) / sorted.length).round();
    String fmt(int v) => v.toString().padLeft(6);
    return '  ${screen.padRight(8)}  ${elementCount.toString().padLeft(5)}  '
        '${fmt(min)}  ${fmt(p50)}  ${fmt(p99)}  ${fmt(max)}  ${fmt(mean)}';
  }
}
