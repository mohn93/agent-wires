import 'dart:convert';
import '../mcp/tool.dart';
import '../session/app_session.dart';

List<Tool> overlayTools(AppSession session) => [
      Tool(
        name: 'set_action_overlay',
        description:
            'Toggles the on-screen action overlay — the ripples, highlight '
            'boxes and flashes the probe draws where you tap, type, point, and '
            'look. It is a visual aid for a human watching the device and '
            'never appears in your `screenshot` or `snapshot`. On by default. '
            'Pass `enabled:false` to turn it off (e.g. for a clean screen '
            'recording) and `true` to turn it back on.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'enabled': {'type': 'boolean'},
          },
          'required': ['enabled'],
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.set_overlay', {
            'enabled': (args['enabled'] == true).toString(),
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
