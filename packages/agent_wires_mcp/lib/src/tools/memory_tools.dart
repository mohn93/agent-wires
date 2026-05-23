// packages/agent_wires_mcp/lib/src/tools/memory_tools.dart
import 'dart:convert';
import '../map/map_record.dart';
import '../map/semantic_map.dart';
import '../mcp/tool.dart';
import '../session/app_session.dart';

List<Tool> memoryTools(SemanticMap map, {AppSession? session}) => [
      Tool(
        name: 'label_element',
        description:
            'Persists a human-readable name for an element so future '
            'snapshots show it as `persistent_label`. Use sparingly — only '
            'when the auto-inferred `label` is ambiguous or missing and you '
            'want to refer to this element by a stable name across sessions. '
            'Provide either `fingerprint` (preferred — stable across snapshots '
            'and rebuilds) or `element_id` from the latest snapshot.',
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
            if (session == null) {
              return _result(jsonEncode({
                'success': false,
                'error': 'fingerprint or element_id required',
              }));
            }
            // Resolve element_id via a live snapshot.
            final vm = await session.ensureReady();
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
        description:
            'Returns all persistent labels you have set via `label_element`. '
            'Pass `route` to scope to one screen. Useful at session start to '
            'remind yourself what custom names exist before snapshotting.',
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
        description:
            'Case-insensitive substring search over your persistent labels. '
            'Use when you remember labeling something but not the exact '
            'screen ("find anything I labeled \'submit\'").',
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
