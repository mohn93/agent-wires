// packages/flutter_qa_mcp/test/tools/memory_tools_test.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter_qa_mcp/src/map/map_record.dart';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:flutter_qa_mcp/src/tools/memory_tools.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late SemanticMap map;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('memory_tools_test_');
    map = SemanticMap(projectRoot: tmp.path);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) async {
    final tool = memoryTools(map).firstWhere((t) => t.name == name);
    final result = await tool.handler(args);
    final text = ((result['content'] as List).first as Map)['text'] as String;
    return jsonDecode(text) as Map<String, dynamic>;
  }

  test('label_element writes a human label and persists to disk', () async {
    final resp = await call('label_element', {
      'fingerprint': 'f_abc',
      'name': 'Checkout',
    });
    expect(resp['success'], isTrue);
    expect(map.get('f_abc')?.humanLabel, 'Checkout');
    expect(File('${tmp.path}/.flutter_qa/map.json').existsSync(), isTrue);
  });

  test('label_element on existing fingerprint updates the label and increments observation_count', () async {
    map.upsert(MapEntry(fingerprint: 'f_x', humanLabel: 'Old', observationCount: 3));
    await call('label_element', {'fingerprint': 'f_x', 'name': 'New'});
    expect(map.get('f_x')?.humanLabel, 'New');
    expect(map.get('f_x')?.observationCount, 4);
  });

  test('get_labels returns all human-labeled entries', () async {
    map.upsert(MapEntry(fingerprint: 'f_1', humanLabel: 'A'));
    map.upsert(MapEntry(fingerprint: 'f_2', humanLabel: 'B'));
    map.upsert(MapEntry(fingerprint: 'f_3'));  // no label — should be excluded
    final resp = await call('get_labels', {});
    final labels = resp['labels'] as List;
    expect(labels, hasLength(2));
  });

  test('recall does a case-insensitive substring search on human_label', () async {
    map.upsert(MapEntry(fingerprint: 'f_1', humanLabel: 'Checkout Button'));
    map.upsert(MapEntry(fingerprint: 'f_2', humanLabel: 'Profile Avatar'));
    final resp = await call('recall', {'query': 'check'});
    final matches = resp['matches'] as List;
    expect(matches, hasLength(1));
    expect((matches.first as Map)['human_label'], 'Checkout Button');
  });

  test('label_element with missing fingerprint returns success:false', () async {
    final resp = await call('label_element', {'name': 'X'});
    expect(resp['success'], isFalse);
  });
}
