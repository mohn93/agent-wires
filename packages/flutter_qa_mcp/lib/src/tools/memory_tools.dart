// packages/flutter_qa_mcp/lib/src/tools/memory_tools.dart
import 'dart:convert';
import '../map/map_record.dart';
import '../map/semantic_map.dart';
import '../mcp/tool.dart';

List<Tool> memoryTools(SemanticMap map) => [
      Tool(
        name: 'label_element',
        description:
            'Persists a human label for an element fingerprint. Subsequent snapshots will use this label.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'fingerprint': {'type': 'string'},
            'name': {'type': 'string'},
            'notes': {'type': 'string'},
          },
          'required': ['fingerprint', 'name'],
        },
        handler: (args) async {
          final fp = args['fingerprint'] as String?;
          final name = args['name'] as String?;
          if (fp == null || name == null) {
            return _result(
                jsonEncode({'success': false, 'error': 'fingerprint and name required'}));
          }
          final existing = map.get(fp);
          if (existing == null) {
            map.upsert(MapEntry(
              fingerprint: fp,
              humanLabel: name,
              observationCount: 1,
            ));
          } else {
            existing.humanLabel = name;
            existing.observationCount += 1;
          }
          await map.save();
          return _result(jsonEncode({'success': true, 'fingerprint': fp, 'label': name}));
        },
      ),
      Tool(
        name: 'get_labels',
        description: 'Returns all persistent labels (entries with human_label set).',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (args) async {
          final labels = map.entries
              .where((e) => e.humanLabel != null)
              .map((e) => e.toJson())
              .toList();
          return _result(jsonEncode({'success': true, 'labels': labels}));
        },
      ),
      Tool(
        name: 'recall',
        description: 'Case-insensitive substring search over human labels.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
          },
          'required': ['query'],
        },
        handler: (args) async {
          final query = (args['query'] as String? ?? '').toLowerCase();
          if (query.isEmpty) {
            return _result(jsonEncode({'success': false, 'error': 'query required'}));
          }
          final matches = map.entries
              .where((e) =>
                  e.humanLabel != null &&
                  e.humanLabel!.toLowerCase().contains(query))
              .map((e) => e.toJson())
              .toList();
          return _result(jsonEncode({'success': true, 'matches': matches}));
        },
      ),
    ];

Map<String, dynamic> _result(String text) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
    };
