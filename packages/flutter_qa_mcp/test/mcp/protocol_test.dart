import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/mcp/tool.dart';
import 'package:test/test.dart';

void main() {
  test('initialize returns server info', () async {
    final p = McpProtocol(tools: const []);
    final resp = await p.handle({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'});
    expect(resp['result'], isNotNull);
    expect(resp['result']['serverInfo']['name'], 'flutter_qa_mcp');
  });

  test('tools/list returns registered tools', () async {
    final p = McpProtocol(tools: [
      Tool(
        name: 'echo',
        description: 'echoes input',
        inputSchema: {'type': 'object'},
        handler: (args) async => {'content': [{'type': 'text', 'text': 'ok'}]},
      ),
    ]);
    final resp = await p.handle({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
    expect((resp['result']['tools'] as List).first['name'], 'echo');
  });

  test('tools/call invokes the handler and returns the result', () async {
    final p = McpProtocol(tools: [
      Tool(
        name: 'echo',
        description: '',
        inputSchema: {'type': 'object'},
        handler: (args) async => {'content': [{'type': 'text', 'text': args['msg'] ?? ''}]},
      ),
    ]);
    final resp = await p.handle({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {'name': 'echo', 'arguments': {'msg': 'hi'}},
    });
    expect(resp['result']['content'][0]['text'], 'hi');
  });

  test('unknown method returns -32601', () async {
    final p = McpProtocol(tools: const []);
    final resp = await p.handle({'jsonrpc': '2.0', 'id': 4, 'method': 'nope'});
    expect(resp['error']['code'], -32601);
  });
}
