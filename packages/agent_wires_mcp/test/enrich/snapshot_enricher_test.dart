import 'package:agent_wires_mcp/src/enrich/snapshot_enricher.dart';
import 'package:agent_wires_mcp/src/map/map_record.dart';
import 'package:agent_wires_mcp/src/map/semantic_map.dart';
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
    final el = elements.first as Map;
    expect(el['label'], 'Remove Item');
    expect(el['label_source'], 'human');
    // Fix 2: persistent_label is set for promoted unresolved elements.
    expect(el['persistent_label'], 'Remove Item');
  });

  test('elements with existing label get persistent_label added without overwriting label', () {
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
    // Fix 2: original label and label_source are preserved; persistent_label is added.
    expect(el['label'], 'Go');
    expect(el['label_source'], 'text_child');
    expect(el['persistent_label'], 'Submit');
  });

  test('dismissed fingerprint is excluded from both elements and unresolved', () {
    final raw = {
      'route': '/home',
      'viewport': {'w': 400, 'h': 800},
      'elements': [],
      'unresolved': [
        {
          'id': 'e_d',
          'fingerprint': 'f_d',
          'widget_type': 'GestureDetector',
          'role': 'tappable',
          'label_source': 'none',
          'enabled': true,
        }
      ],
    };
    final map = SemanticMap(projectRoot: '.');
    map.upsert(MapEntry(fingerprint: 'f_d', dismissed: true));
    final enriched = SnapshotEnricher.enrich(raw: raw, map: map);
    // Fix 3: dismissed element disappears entirely from output.
    expect((enriched['unresolved'] as List), isEmpty);
    expect((enriched['elements'] as List), isEmpty);
  });
}
