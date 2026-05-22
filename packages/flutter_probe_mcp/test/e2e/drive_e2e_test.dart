import 'dart:convert';
import 'dart:io';
import 'package:flutter_probe_mcp/src/map/semantic_map.dart';
import 'package:flutter_probe_mcp/src/mcp/protocol.dart';
import 'package:flutter_probe_mcp/src/runner/flutter_runner.dart';
import 'package:flutter_probe_mcp/src/tools/action_tools.dart';
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
    late VmClient vm;
    late McpProtocol protocol;

    setUpAll(() async {
      await harness.start();
      vm = await VmClient.connect(harness.vmServiceUri);
      final map = SemanticMap(projectRoot: '/tmp');
      protocol = McpProtocol(tools: [
        ...perceptionTools(vm, map),
        ...actionTools(vm),
        ...syncTools(vm),
      ]);
    });

    tearDownAll(() async {
      await vm.dispose();
      await harness.stop();
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

    test(
        'snapshot → tap "Go to cart" → wait_for_route → snapshot finds cart content',
        () async {
      final home = await callTool('snapshot', {});
      final goToCart = (home['elements'] as List).firstWhere(
        (e) => (e as Map)['label'] == 'Go to cart',
      ) as Map;
      final id = goToCart['id'] as String;

      final tapResp = await callTool('tap', {'element_id': id});
      expect(tapResp['success'], isTrue);

      final routeResp = await callTool('wait_for_route', {
        'route': '/cart',
        'timeout_ms': 5000,
      });
      expect(routeResp['matched'], isTrue);

      final cart = await callTool('snapshot', {});
      expect(cart['route'], '/cart');
      // The cart screen has two ListTile items + two delete GestureDetectors.
      // We check for the presence of any 'tappable' role (the delete buttons).
      final hasTappable = (cart['elements'] as List).any(
        (e) => (e as Map)['role'] == 'tappable',
      );
      expect(hasTappable, isTrue);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }, tags: ['e2e']);
}
