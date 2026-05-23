import 'tool.dart';
import '../version.dart';

class McpProtocol {
  McpProtocol({required List<Tool> tools}) : _tools = {for (final t in tools) t.name: t};

  final Map<String, Tool> _tools;

  Future<Map<String, dynamic>?> handle(Map<String, dynamic> req) async {
    if (!req.containsKey('id')) return null; // notification — no response per MCP/JSON-RPC spec
    final id = req['id'];
    final method = req['method'] as String?;
    try {
      switch (method) {
        case 'initialize':
          return _ok(id, {
            'protocolVersion': '2025-06-18',
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'agent_wires_mcp', 'version': packageVersion},
          });
        case 'tools/list':
          return _ok(id, {'tools': _tools.values.map((t) => t.toDescriptor()).toList()});
        case 'tools/call':
          final params = (req['params'] as Map?) ?? const {};
          final name = params['name'] as String?;
          final args = (params['arguments'] as Map?)?.cast<String, dynamic>() ?? const {};
          final tool = name == null ? null : _tools[name];
          if (tool == null) return _err(id, -32602, 'unknown tool: $name');
          final result = await tool.handler(args);
          return _ok(id, result);
        default:
          return _err(id, -32601, 'unknown method: $method');
      }
    } catch (e) {
      return _err(id, -32603, e.toString());
    }
  }

  Map<String, dynamic> _ok(dynamic id, Map<String, dynamic> result) =>
      {'jsonrpc': '2.0', 'id': id, 'result': result};

  Map<String, dynamic> _err(dynamic id, int code, String message) =>
      {'jsonrpc': '2.0', 'id': id, 'error': {'code': code, 'message': message}};
}
