import 'dart:convert';
import '../mcp/tool.dart';
import '../session/app_session.dart';

List<Tool> syncTools(AppSession session) => [
      Tool(
        name: 'wait_for_idle',
        description: 'Returns when no pending frames, no running animations, and no in-flight HTTP. Bounded by timeout_ms (default 10000).',
        inputSchema: {
          'type': 'object',
          'properties': {'timeout_ms': {'type': 'integer'}},
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.wait_for_idle', {
            if (args['timeout_ms'] != null) 'timeout_ms': args['timeout_ms'].toString(),
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'wait_for_route',
        description: 'Returns when the current named route matches `route`. Bounded by timeout_ms.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'route': {'type': 'string'},
            'timeout_ms': {'type': 'integer'},
          },
          'required': ['route'],
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.wait_for_route', {
            'route': args['route'],
            if (args['timeout_ms'] != null) 'timeout_ms': args['timeout_ms'].toString(),
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'wait_for_element',
        description: 'Returns when an element matching `label` and/or `role` appears in the snapshot.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'label': {'type': 'string'},
            'role': {'type': 'string'},
            'timeout_ms': {'type': 'integer'},
          },
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.wait_for_element', {
            if (args['label'] != null) 'label': args['label'],
            if (args['role'] != null) 'role': args['role'],
            if (args['timeout_ms'] != null) 'timeout_ms': args['timeout_ms'].toString(),
          });
          return _result(jsonEncode(json));
        },
      ),
    ];

Map<String, dynamic> _result(String text) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
    };
