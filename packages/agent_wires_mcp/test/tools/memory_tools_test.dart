// packages/agent_wires_mcp/test/tools/memory_tools_test.dart
import 'dart:io';
import 'dart:convert';
import 'package:agent_wires_mcp/src/map/map_record.dart';
import 'package:agent_wires_mcp/src/map/semantic_map.dart';
import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/tools/memory_tools.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

// A fake VmClient that returns a canned snapshot without a real VM connection.
class _FakeVm extends VmClient {
  _FakeVm(this._snapshot) : super.test();

  final Map<String, dynamic> _snapshot;

  @override
  Future<Map<String, dynamic>> callExtension(
    String name, [
    Map<String, dynamic>? args,
  ]) async =>
      _snapshot;
}

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

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> args, {
    VmClient? vm,
  }) async {
    final session = vm == null ? null : AppSession.attached(vm);
    final tool = memoryTools(map, session: session).firstWhere((t) => t.name == name);
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

  test('label_element with missing fingerprint and no vm returns success:false', () async {
    final resp = await call('label_element', {'name': 'X'});
    expect(resp['success'], isFalse);
  });

  test('label_element resolves element_id via vm snapshot', () async {
    final fakeSnapshot = {
      'elements': [
        {'id': 'elem_42', 'fingerprint': 'fp_resolved', 'type': 'Button'},
      ],
      'unresolved': <dynamic>[],
    };
    final fakeVm = _FakeVm(fakeSnapshot);

    final resp = await call(
      'label_element',
      {'element_id': 'elem_42', 'name': 'Add to Cart'},
      vm: fakeVm,
    );
    expect(resp['success'], isTrue);
    expect(resp['fingerprint'], 'fp_resolved');
    expect(map.get('fp_resolved')?.humanLabel, 'Add to Cart');
  });

  test('label_element returns error when element_id not in snapshot', () async {
    final fakeSnapshot = {
      'elements': <dynamic>[],
      'unresolved': <dynamic>[],
    };
    final fakeVm = _FakeVm(fakeSnapshot);

    final resp = await call(
      'label_element',
      {'element_id': 'nonexistent', 'name': 'Whatever'},
      vm: fakeVm,
    );
    expect(resp['success'], isFalse);
    expect(resp['error'], contains('element_id not found'));
  });

  test('get_labels filters by route when route is provided', () async {
    map.upsert(MapEntry(
      fingerprint: 'f_cart',
      humanLabel: 'Cart Button',
      screenContext: '/cart',
    ));
    map.upsert(MapEntry(
      fingerprint: 'f_home',
      humanLabel: 'Home Header',
      screenContext: '/home',
    ));
    final resp = await call('get_labels', {'route': '/cart'});
    final labels = resp['labels'] as List;
    expect(labels, hasLength(1));
    expect((labels.first as Map)['screen_context'], '/cart');
  });
}
