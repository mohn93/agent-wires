import 'dart:convert';
import '../mcp/tool.dart';
import '../session/app_session.dart';

List<Tool> overlayTools(AppSession session) => [
      Tool(
        name: 'set_action_overlay',
        description:
            'Shows or hides the on-screen action overlay in the running app. '
            'Pass `enabled: true` to show the overlay and `enabled: false` to '
            'hide it. The overlay visualises agent interactions in real time '
            'and is useful for demos and debugging.',
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
