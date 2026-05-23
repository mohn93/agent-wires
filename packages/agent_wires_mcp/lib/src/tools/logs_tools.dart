import 'dart:convert';

import '../mcp/tool.dart';
import '../session/app_session.dart';

List<Tool> logsTools(AppSession session) => [
      Tool(
        name: 'get_network',
        description:
            'Returns recent HTTP exchanges (method, url, status_code, '
            'duration_ms, error). Best used right after an action to see '
            'what the tap triggered on the wire ("did Sign In actually '
            'POST /login?"). Pagination: pass `since` = the `cursor` from '
            'the previous response to drain only new exchanges; otherwise '
            'the most recent `limit` (default 100) are returned. Only HTTP '
            'going through Dart\'s HttpClient is captured; native iOS/Android '
            'network calls and WebSocket frames are not.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'since': {
              'type': 'string',
              'description':
                  'Return only exchanges started strictly after this timestamp. Pass the `cursor` from a previous response to paginate.',
            },
            'limit': {
              'type': 'number',
              'description': 'Maximum entries to return. Default 100.',
            },
          },
        },
        handler: (args) async {
          final params = <String, String>{};
          final since = args['since'];
          final limit = args['limit'];
          if (since is String && since.isNotEmpty) params['since'] = since;
          if (limit is num) params['limit'] = limit.toInt().toString();
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.get_network', params);
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'get_logs',
        description:
            'Returns recent runtime log entries (debugPrint output, '
            'FlutterError errors, uncaught zone errors). Use this when '
            'something appears stuck or broken — the app may have logged a '
            'failure that explains what you are seeing on screen. '
            'Pagination: pass `since` = the `cursor` from a previous '
            'response; otherwise the most recent `limit` (default 200) are '
            'returned. Plain `print()` calls outside the probe\'s zone are '
            'NOT captured — only `debugPrint`.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'since': {
              'type': 'string',
              'description':
                  'Return only entries strictly after this timestamp. Pass the `cursor` from a previous response to paginate.',
            },
            'limit': {
              'type': 'number',
              'description': 'Maximum entries to return. Default 200.',
            },
          },
        },
        handler: (args) async {
          final params = <String, String>{};
          final since = args['since'];
          final limit = args['limit'];
          if (since is String && since.isNotEmpty) params['since'] = since;
          if (limit is num) params['limit'] = limit.toInt().toString();
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.get_logs', params);
          return _result(jsonEncode(json));
        },
      ),
    ];

Map<String, dynamic> _result(String text) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
    };
