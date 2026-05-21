import 'dart:convert';
import '../enrich/som_annotator.dart';
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
        description:
            'Returns a base64-encoded PNG of the current screen. If annotated=true, overlays numbered Set-of-Mark boxes using the current snapshot.',
        inputSchema: {
          'type': 'object',
          'properties': {'annotated': <String, dynamic>{'type': 'boolean'}},
        },
        handler: (args) async {
          final shotJson = await vm.callExtension('ext.qa.screenshot');
          final annotated = args['annotated'] == true;
          if (!annotated) {
            return _toolResult(jsonEncode(shotJson));
          }
          final snapJson = await vm.callExtension('ext.qa.snapshot');
          final elements = ((snapJson['elements'] as List?) ?? const [])
              .cast<Map<String, dynamic>>();
          final pngB64 = shotJson['data_base64'] as String;
          final annotatedPng =
              SomAnnotator.annotate(pngBase64: pngB64, elements: elements);
          return _toolResult(jsonEncode({
            ...shotJson,
            'data_base64': annotatedPng,
            'annotated': true,
            'element_count': elements.length,
          }));
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
