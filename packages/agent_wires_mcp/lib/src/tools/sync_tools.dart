import 'dart:convert';
import '../mcp/tool.dart';
import '../session/app_session.dart';

List<Tool> syncTools(AppSession session) => [
      Tool(
        name: 'wait_for_idle',
        description:
            'GENERIC POST-ACTION SYNC. Returns when there are no pending '
            'frames, no running animations, and no in-flight HTTP. Use this '
            'after any action when you do not know specifically what to wait '
            'for ("I tapped Submit, now wait for things to settle"). Bounded '
            'by `timeout_ms` (default 10000).',
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
        description:
            'NAVIGATION SYNC. Returns when the current named route matches '
            '`route`. Use after taps that navigate (Sign In → MainRoute, '
            'tapping a list item → DetailRoute) when you know the route '
            'name. More precise than `wait_for_idle` — does not return '
            'until the new screen is mounted.',
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
        description:
            'CONTENT SYNC. Returns when an element matching `label` and/or '
            '`role` appears in the snapshot. Use when you are waiting for a '
            'specific widget to render (a toast, a row in a list that loads '
            'async, a button that becomes enabled). Polls the snapshot — '
            'cheaper than re-snapshotting in a loop yourself.',
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
