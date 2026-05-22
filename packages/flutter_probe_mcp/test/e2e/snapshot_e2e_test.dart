import 'dart:convert';
import 'dart:io';
import 'package:flutter_probe_mcp/src/map/semantic_map.dart';
import 'package:flutter_probe_mcp/src/mcp/protocol.dart';
import 'package:flutter_probe_mcp/src/runner/flutter_runner.dart';
import 'package:flutter_probe_mcp/src/tools/perception.dart';
import 'package:flutter_probe_mcp/src/tools/sync_tools.dart';
import 'package:flutter_probe_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  group('e2e', () {
    final harness = FlutterRunner(
      workingDirectory: '../../examples/demo_app',
      deviceId: Platform.environment['FLUTTER_QA_E2E_DEVICE'],
    );

    setUpAll(() async {
      await harness.start();
    });

    tearDownAll(() async {
      await harness.stop();
    });

    test('snapshot tool returns elements from demo app home screen', () async {
      final vm = await VmClient.connect(harness.vmServiceUri);
      final map = SemanticMap(projectRoot: '/tmp');
      final protocol = McpProtocol(tools: [
        ...perceptionTools(vm, map),
        ...syncTools(vm),
      ]);
      // Let the first frame finish painting before querying the tree.
      await protocol.handle({
        'jsonrpc': '2.0',
        'id': 0,
        'method': 'tools/call',
        'params': {
          'name': 'wait_for_idle',
          'arguments': {'timeout_ms': 5000},
        },
      });
      final resp = (await protocol.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': 'snapshot', 'arguments': {}},
      }))!;
      // Debug: surface the full response if it doesn't look like a tool result.
      if (resp['result'] is! Map || (resp['result'] as Map)['content'] is! List) {
        fail('unexpected response shape: $resp');
      }
      final text =
          ((resp['result'] as Map)['content'] as List).first['text'] as String;
      final snap = jsonDecode(text) as Map<String, dynamic>;
      final elements = snap['elements'] as List;
      expect(elements, isNotEmpty);
      expect(
        elements.any((e) => (e as Map)['label'] == 'Go to cart'),
        isTrue,
        reason: 'expected the home-screen button label to appear',
      );
      await vm.dispose();
    }, timeout: const Timeout(Duration(minutes: 8)));
  }, tags: ['e2e']);
}
