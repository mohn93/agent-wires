import 'dart:convert';
import 'dart:io';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/runner/flutter_runner.dart';
import 'package:flutter_qa_mcp/src/tools/action_tools.dart';
import 'package:flutter_qa_mcp/src/tools/memory_tools.dart';
import 'package:flutter_qa_mcp/src/tools/perception.dart';
import 'package:flutter_qa_mcp/src/tools/sync_tools.dart';
import 'package:flutter_qa_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  group('e2e', () {
    final harness = FlutterRunner(
      workingDirectory: '../../examples/demo_app',
      deviceId: Platform.environment['FLUTTER_QA_E2E_DEVICE'],
    );
    late VmClient vm;
    late McpProtocol protocol;
    late Directory tmp;
    late SemanticMap map;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('aug_e2e_');
      map = SemanticMap(projectRoot: tmp.path);
      await harness.start();
      vm = await VmClient.connect(harness.vmServiceUri);
      protocol = McpProtocol(tools: [
        ...perceptionTools(vm, map),
        ...actionTools(vm),
        ...syncTools(vm),
        ...memoryTools(map, vm: vm),
      ]);
    });

    tearDownAll(() async {
      await vm.dispose();
      await harness.stop();
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

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

    test('label_element promotes an unresolved element to resolved', () async {
      final home = await callTool('snapshot', {});
      final goToCart = (home['elements'] as List).firstWhere(
        (e) => (e as Map)['label'] == 'Go to cart',
      ) as Map;
      await callTool('tap', {'element_id': goToCart['id']});
      await callTool('wait_for_route', {'route': '/cart', 'timeout_ms': 5000});

      final cart = await callTool('snapshot', {});
      final unresolved = (cart['unresolved'] as List? ?? []);
      expect(unresolved, isNotEmpty,
          reason: 'expected at least one unresolved tappable on cart screen');

      final target = unresolved.first as Map;
      final fp = target['fingerprint'] as String;

      final labelResp = await callTool('label_element', {
        'fingerprint': fp,
        'name': 'Delete Item',
      });
      expect(labelResp['success'], isTrue);

      final after = await callTool('snapshot', {});
      final resolvedMatch = (after['elements'] as List).any(
        (e) => (e as Map)['fingerprint'] == fp && e['label'] == 'Delete Item',
      );
      expect(resolvedMatch, isTrue);

      final stillUnresolved = (after['unresolved'] as List).any(
        (e) => (e as Map)['fingerprint'] == fp,
      );
      expect(stillUnresolved, isFalse);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }, tags: ['e2e']);
}
