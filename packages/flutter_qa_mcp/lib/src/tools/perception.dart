import 'dart:convert';
import '../mcp/tool.dart';
import '../vm/client.dart';

List<Tool> perceptionTools(VmClient vm) => [
      Tool(
        name: 'snapshot',
        description: 'Returns the denoised semantic tree of the currently visible screen.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          final json = await vm.callExtension('ext.qa.snapshot');
          return _toolResult(jsonEncode(json));
        },
      ),
      Tool(
        name: 'inspect',
        description: 'Returns full widget chain and properties for a single element_id.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'element_id': {'type': 'string'},
          },
          'required': ['element_id'],
        },
        handler: (args) async {
          final id = args['element_id'] as String?;
          if (id == null) {
            return _toolError('element_id required');
          }
          final json = await vm.callExtension('ext.qa.inspect', {'element_id': id});
          return _toolResult(jsonEncode(json));
        },
      ),
      Tool(
        name: 'screenshot',
        description: 'Returns a base64-encoded PNG of the current screen.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          final json = await vm.callExtension('ext.qa.screenshot');
          return _toolResult(jsonEncode(json));
        },
      ),
    ];

Map<String, dynamic> _toolResult(String text) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
    };

Map<String, dynamic> _toolError(String message) => {
      'isError': true,
      'content': [
        {'type': 'text', 'text': message},
      ],
    };
