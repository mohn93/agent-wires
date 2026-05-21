// packages/flutter_qa_mcp/test/e2e/snapshot_e2e_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/tools/perception.dart';
import 'package:flutter_qa_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  group('e2e', () {
    late Process flutter;
    late Uri vmUri;

    setUpAll(() async {
      flutter = await Process.start(
        'flutter',
        ['test', 'integration_test/qa_smoke_test.dart', '--machine'],
        workingDirectory: '../../examples/demo_app',
      );
      final completer = Completer<Uri>();
      flutter.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        final m = _tryParse(line);
        final uri = m?['params']?['observatoryUri'] as String?;
        if (uri != null && !completer.isCompleted) {
          completer.complete(Uri.parse(uri));
        }
      });
      vmUri = await completer.future.timeout(const Duration(seconds: 60));
    });

    tearDownAll(() async {
      flutter.kill();
      await flutter.exitCode;
    });

    test('snapshot tool returns elements from demo app home screen', () async {
      final vm = await VmClient.connect(vmUri);
      final map = SemanticMap(projectRoot: '/tmp');
      final protocol = McpProtocol(tools: perceptionTools(vm, map));
      final resp = (await protocol.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': 'snapshot', 'arguments': {}},
      }))!;
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
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, tags: ['e2e']);
}

Map<String, dynamic>? _tryParse(String line) {
  try {
    final v = jsonDecode(line);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}
