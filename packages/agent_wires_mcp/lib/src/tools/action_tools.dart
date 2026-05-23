import 'dart:convert';
import '../mcp/tool.dart';
import '../session/app_session.dart';

List<Tool> actionTools(AppSession session) => [
      Tool(
        name: 'tap',
        description:
            'Synthesizes a tap at the center of an element. Pass the '
            '`element_id` from the latest `snapshot` (ids expire after a '
            'frame). After tapping, call `wait_for_idle` or '
            '`wait_for_route`, then `snapshot` again before the next action.',
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
        description:
            'Holds a press at the center of an element for `duration_ms` '
            '(default 600). Use for context menus, drag handles, or any '
            'gesture that requires holding. For a normal tap use `tap`.',
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
        description:
            'Drags from (from_x, from_y) to (to_x, to_y) in global screen '
            'coordinates. Use this for: dismissing sheets, swipe-to-delete, '
            'page-view paging, slider dragging. For scrolling a list, prefer '
            '`scroll` — it finds the scrollable for you.',
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
        description:
            'Focuses a TextField (`role: textfield`) and replaces its '
            'contents with `text`. If you do not see a textfield in '
            '`snapshot.elements[]`, check `snapshot.unresolved[]` — hidden '
            'text inputs (pin codes, autocomplete) often live there. After '
            'typing, call `wait_for_idle` before the next action.',
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
        description:
            'Clears a TextField. Use before `enter_text` if you want to '
            'replace existing content, though `enter_text` already replaces '
            'contents by default — this is mainly for "leave the field '
            'empty" scenarios.',
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
        description:
            'Scrolls the nearest visible Scrollable in `direction` (up | '
            'down | left | right) by `distance` logical pixels (default 300). '
            'If you pass `element_id`, scrolls the Scrollable inside that '
            'element instead — useful when multiple lists are on screen. '
            'Always re-`snapshot` after scrolling; new elements come into '
            'view and old ones leave.',
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
        description:
            'Equivalent to the Android system back button — pops the current '
            'route in the navigator stack. On iOS this still works because '
            'it uses the Navigator API directly, not the platform back '
            'channel. Use this instead of tapping a custom back arrow when '
            'you just want to go up one screen.',
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
