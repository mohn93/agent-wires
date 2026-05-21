// packages/flutter_qa_mcp/lib/src/tools/memory_tools.dart
import 'dart:convert';
import '../map/map_record.dart';
import '../map/semantic_map.dart';
import '../mcp/tool.dart';
import '../vm/client.dart';

List<Tool> memoryTools(SemanticMap map, {VmClient? vm}) => [
      Tool(
        name: 'label_element',
        description:
            'Persists a human label for an element. Provide either `fingerprint` (preferred — stable across snapshots) or `element_id` (from a recent snapshot).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'fingerprint': {'type': 'string'},
            'element_id': {'type': 'string'},
            'name': {'type': 'string'},
            'notes': {'type': 'string'},
          },
          'required': ['name'],
        },
        handler: (args) async {
          final name = args['name'] as String?;
          if (name == null) {
            return _result(
                jsonEncode({'success': false, 'error': 'name required'}));
          }

          String? fp = args['fingerprint'] as String?;

          if (fp == null) {
            final elementId = args['element_id'] as String?;
            if (elementId == null) {
              return _result(jsonEncode({
                'success': false,
                'error': 'fingerprint or element_id required',
              }));
            }
            if (vm == null) {
              return _result(jsonEncode({
                'success': false,
                'error': 'fingerprint or element_id required',
              }));
            }
            // Resolve element_id via a live snapshot.
            final snapshot = await vm.callExtension('ext.qa.snapshot');
            final elements = <Map<String, dynamic>>[];
            final rawElements = snapshot['elements'];
            if (rawElements is List) {
              elements.addAll(rawElements.cast<Map<String, dynamic>>());
            }
            final rawUnresolved = snapshot['unresolved'];
            if (rawUnresolved is List) {
              elements.addAll(rawUnresolved.cast<Map<String, dynamic>>());
            }
            final match = elements.cast<Map<String, dynamic>?>().firstWhere(
                  (e) => e != null && e['id'] == elementId,
                  orElse: () => null,
                );
            if (match == null) {
              return _result(jsonEncode({
                'success': false,
                'error': 'element_id not found in current snapshot',
              }));
            }
            fp = match['fingerprint'] as String?;
            if (fp == null) {
              return _result(jsonEncode({
                'success': false,
                'error': 'element_id not found in current snapshot',
              }));
            }
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
        description: 'Returns persistent labels (entries with human_label set). Pass `route` to filter by screen_context.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'route': {'type': 'string'},
          },
        },
        handler: (args) async {
          final route = args['route'] as String?;
          final labels = map.entries
              .where((e) => e.humanLabel != null)
              .where((e) =>
                  route == null ||
                  route.isEmpty ||
                  e.screenContext == route)
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
