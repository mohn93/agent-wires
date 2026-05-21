// packages/flutter_qa_mcp/test/e2e/drive_e2e_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/tools/action_tools.dart';
import 'package:flutter_qa_mcp/src/tools/perception.dart';
import 'package:flutter_qa_mcp/src/tools/sync_tools.dart';
import 'package:flutter_qa_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  group('e2e', () {
    late Process flutter;
    late Uri vmUri;
    late VmClient vm;
    late McpProtocol protocol;

    setUpAll(() async {
      flutter = await Process.start(
        'flutter',
        ['test', 'integration_test/qa_smoke_test.dart', '--machine'],
        workingDirectory: '../../examples/demo_app',
      );
      final completer = Completer<Uri>();
      flutter.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        try {
          final m = jsonDecode(line);
          final uri = m is Map ? (m['params']?['observatoryUri'] as String?) : null;
          if (uri != null && !completer.isCompleted) completer.complete(Uri.parse(uri));
        } catch (_) {}
      });
      vmUri = await completer.future.timeout(const Duration(seconds: 60));
      vm = await VmClient.connect(vmUri);
      protocol = McpProtocol(tools: [
        ...perceptionTools(vm),
        ...actionTools(vm),
        ...syncTools(vm),
      ]);
    });

    tearDownAll(() async {
      await vm.dispose();
      flutter.kill();
      await flutter.exitCode;
    });

    Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args) async {
      final resp = await protocol.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': name, 'arguments': args},
      });
      final text = ((resp!['result'] as Map)['content'] as List).first['text'] as String;
      return jsonDecode(text) as Map<String, dynamic>;
    }

    test('snapshot → tap "Go to cart" → wait_for_route → snapshot finds cart content', () async {
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
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, tags: ['e2e']);
}
