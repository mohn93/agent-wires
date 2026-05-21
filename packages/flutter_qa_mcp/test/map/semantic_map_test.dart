import 'dart:io';
import 'package:flutter_qa_mcp/src/map/map_record.dart';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('flutter_qa_map_test_');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('save then load round-trips entries', () async {
    final map = SemanticMap(projectRoot: tmp.path);
    map.upsert(MapEntry(
      fingerprint: 'f_abc123',
      humanLabel: 'Checkout',
      observationCount: 7,
    ));
    await map.save();

    final fresh = SemanticMap(projectRoot: tmp.path);
    await fresh.load();
    final entry = fresh.get('f_abc123');
    expect(entry, isNotNull);
    expect(entry!.humanLabel, 'Checkout');
    expect(entry.observationCount, 7);
  });

  test('load on missing file is a no-op', () async {
    final map = SemanticMap(projectRoot: tmp.path);
    await map.load();
    expect(map.entries, isEmpty);
  });

  test('save creates .flutter_qa/map.json with parents as needed', () async {
    final map = SemanticMap(projectRoot: tmp.path);
    map.upsert(MapEntry(fingerprint: 'f_x'));
    await map.save();
    expect(File('${tmp.path}/.flutter_qa/map.json').existsSync(), isTrue);
  });
}
