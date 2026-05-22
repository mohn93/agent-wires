import 'dart:convert';

import '../mcp/tool.dart';
import '../vm/client.dart';

List<Tool> logsTools(VmClient vm) => [
      Tool(
        name: 'get_network',
        description:
            'Returns recent HTTP exchanges (method, url, status_code, duration_ms, error). Use `since` (ISO-8601 timestamp from a previous response\'s `cursor`) to drain only new exchanges; otherwise the most recent `limit` are returned. Useful for watching what a tap triggered on the wire.',
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
          final json = await vm.callExtension('ext.qa.get_network', params);
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'get_logs',
        description:
            'Returns recent runtime log entries (debugPrint output, FlutterError errors, uncaught zone errors). Use `since` (ISO-8601 timestamp from a previous response\'s `cursor` field) to fetch only new entries; otherwise the most recent `limit` entries are returned.',
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
