import 'package:flutter_qa_mcp/src/enrich/snapshot_enricher.dart';
import 'package:flutter_qa_mcp/src/map/map_record.dart';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:test/test.dart';

void main() {
  test('unresolved gains source_location proposal when creation_location parseable', () {
    final raw = {
      'route': '/cart',
      'viewport': {'w': 400, 'h': 800},
      'elements': [],
      'unresolved': [
        {
          'id': 'e_0',
          'fingerprint': 'f_x',
          'widget_type': 'GestureDetector',
          'role': 'tappable',
          'label_source': 'none',
          'creation_location': 'test/fixtures/sample_widget_file.dart:5:12',
          'enabled': true,
        }
      ],
    };
    final map = SemanticMap(projectRoot: '.');
    final enriched = SnapshotEnricher.enrich(raw: raw, map: map);
    final unresolved = enriched['unresolved'] as List;
    expect(unresolved, hasLength(1));
    final proposals = (unresolved.first as Map)['proposals'] as List;
    expect(proposals, isNotEmpty);
    expect((proposals.first as Map)['source'], 'source_location');
  });

  test('human_label promotes an unresolved element to resolved', () {
    final raw = {
      'route': '/cart',
      'viewport': {'w': 400, 'h': 800},
      'elements': [],
      'unresolved': [
        {
          'id': 'e_0',
          'fingerprint': 'f_y',
          'widget_type': 'GestureDetector',
          'role': 'tappable',
          'label_source': 'none',
          'enabled': true,
        }
      ],
    };
    final map = SemanticMap(projectRoot: '.');
    map.upsert(MapEntry(fingerprint: 'f_y', humanLabel: 'Remove Item'));
    final enriched = SnapshotEnricher.enrich(raw: raw, map: map);
    expect((enriched['unresolved'] as List), isEmpty);
    final elements = enriched['elements'] as List;
    expect(elements, hasLength(1));
    expect((elements.first as Map)['label'], 'Remove Item');
    expect((elements.first as Map)['label_source'], 'human');
  });

  test('elements with existing label get their human_label overridden if present', () {
    final raw = {
      'elements': [
        {
          'id': 'e_0',
          'fingerprint': 'f_z',
          'widget_type': 'ElevatedButton',
          'label': 'Go',
          'label_source': 'text_child',
          'enabled': true,
        },
      ],
      'unresolved': [],
    };
    final map = SemanticMap(projectRoot: '.');
    map.upsert(MapEntry(fingerprint: 'f_z', humanLabel: 'Submit'));
    final enriched = SnapshotEnricher.enrich(raw: raw, map: map);
    final el = (enriched['elements'] as List).first as Map;
    expect(el['label'], 'Submit');
    expect(el['label_source'], 'human');
  });
}
