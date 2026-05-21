// packages/flutter_qa_mcp/test/e2e/augmentation_e2e_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/tools/action_tools.dart';
import 'package:flutter_qa_mcp/src/tools/memory_tools.dart';
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
    late Directory tmp;
    late SemanticMap map;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('aug_e2e_');
      map = SemanticMap(projectRoot: tmp.path);
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
        ...perceptionTools(vm, map),
        ...actionTools(vm),
        ...syncTools(vm),
        ...memoryTools(map),
      ]);
    });

    tearDownAll(() async {
      await vm.dispose();
      flutter.kill();
      await flutter.exitCode;
      if (tmp.existsSync()) await tmp.delete(recursive: true);
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

    test('label_element promotes an unresolved element to resolved', () async {
      // Step 1: navigate to cart screen so we have unresolved delete buttons.
      final home = await callTool('snapshot', {});
      final goToCart = (home['elements'] as List).firstWhere(
        (e) => (e as Map)['label'] == 'Go to cart',
      ) as Map;
      await callTool('tap', {'element_id': goToCart['id']});
      await callTool('wait_for_route', {'route': '/cart', 'timeout_ms': 5000});

      // Step 2: snapshot the cart screen and expect at least one unresolved element.
      final cart = await callTool('snapshot', {});
      final unresolved = (cart['unresolved'] as List? ?? []);
      expect(unresolved, isNotEmpty,
          reason: 'expected at least one unresolved tappable on cart screen');

      final target = unresolved.first as Map;
      final fp = target['fingerprint'] as String;

      // Step 3: label it.
      final labelResp = await callTool('label_element', {
        'fingerprint': fp,
        'name': 'Delete Item',
      });
      expect(labelResp['success'], isTrue);

      // Step 4: snapshot again and confirm the element moved to elements[] with the new label.
      final after = await callTool('snapshot', {});
      final resolvedMatch = (after['elements'] as List).any(
        (e) => (e as Map)['fingerprint'] == fp && e['label'] == 'Delete Item',
      );
      expect(resolvedMatch, isTrue);

      // Step 5: confirm it no longer appears in unresolved.
      final stillUnresolved = (after['unresolved'] as List).any(
        (e) => (e as Map)['fingerprint'] == fp,
      );
      expect(stillUnresolved, isFalse);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }, tags: ['e2e']);
}
