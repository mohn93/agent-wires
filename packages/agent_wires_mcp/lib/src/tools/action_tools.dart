import 'dart:convert';
import '../mcp/tool.dart';
import '../session/app_session.dart';

List<Tool> actionTools(AppSession session) => [
      Tool(
        name: 'tap',
        description: 'Synthesizes a tap at the center of the given element.',
        inputSchema: {
          'type': 'object',
          'properties': {'element_id': {'type': 'string'}},
          'required': ['element_id'],
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.tap', {
            'element_id': args['element_id'],
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'long_press',
        description: 'Holds a press at the center of an element for duration_ms (default 600).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'element_id': {'type': 'string'},
            'duration_ms': {'type': 'integer'},
          },
          'required': ['element_id'],
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.long_press', {
            'element_id': args['element_id'],
            if (args['duration_ms'] != null) 'duration_ms': args['duration_ms'].toString(),
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'swipe',
        description: 'Drags from (from_x, from_y) to (to_x, to_y) in global coordinates.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'from_x': {'type': 'number'},
            'from_y': {'type': 'number'},
            'to_x': {'type': 'number'},
            'to_y': {'type': 'number'},
            'duration_ms': {'type': 'integer'},
          },
          'required': ['from_x', 'from_y', 'to_x', 'to_y'],
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.swipe', {
            'from_x': args['from_x'].toString(),
            'from_y': args['from_y'].toString(),
            'to_x': args['to_x'].toString(),
            'to_y': args['to_y'].toString(),
            if (args['duration_ms'] != null) 'duration_ms': args['duration_ms'].toString(),
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'enter_text',
        description: 'Focuses the TextField at element_id and replaces its contents.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'element_id': {'type': 'string'},
            'text': {'type': 'string'},
          },
          'required': ['element_id', 'text'],
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.enter_text', {
            'element_id': args['element_id'],
            'text': args['text'],
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'clear_text',
        description: 'Clears the TextField at element_id.',
        inputSchema: {
          'type': 'object',
          'properties': {'element_id': {'type': 'string'}},
          'required': ['element_id'],
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.clear_text', {
            'element_id': args['element_id'],
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'scroll',
        description: 'Scrolls the nearest visible Scrollable (or one inside element_id).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'direction': {
              'type': 'string',
              'enum': ['up', 'down', 'left', 'right'],
            },
            'distance': {'type': 'number'},
            'element_id': {'type': 'string'},
          },
          'required': ['direction'],
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.scroll', {
            'direction': args['direction'],
            if (args['distance'] != null) 'distance': args['distance'].toString(),
            if (args['element_id'] != null) 'element_id': args['element_id'],
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'press_back',
        description: 'Equivalent to Android back button — pops the current route.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.press_back');
          return _result(jsonEncode(json));
        },
      ),
    ];

Map<String, dynamic> _result(String text) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
    };
