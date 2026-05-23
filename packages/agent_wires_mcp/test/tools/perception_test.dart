import 'dart:convert';
import 'dart:io';

import 'package:agent_wires_mcp/src/map/semantic_map.dart';
import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/tools/perception.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

// A 1×1 transparent PNG, base64-encoded. The smallest valid PNG.
const _onePxPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkAAIAAAoAAv/lxKUAAAAASUVORK5CYII=';

class _FakeVm extends VmClient {
  _FakeVm(this._responses) : super.test();

  final Map<String, Map<String, dynamic>> _responses;

  @override
  Future<Map<String, dynamic>> callExtension(
    String name, [
    Map<String, dynamic>? args,
  ]) async {
    final r = _responses[name];
    if (r == null) {
      throw StateError('no canned response for $name');
    }
    return r;
  }
}

void main() {
  late SemanticMap map;
  late Directory tmpMapDir;

  setUp(() async {
    tmpMapDir = await Directory.systemTemp.createTemp('perception_test_');
    map = SemanticMap(projectRoot: tmpMapDir.path);
  });

  tearDown(() async {
    if (tmpMapDir.existsSync()) await tmpMapDir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> args,
    VmClient vm,
  ) async {
    final tool = perceptionTools(AppSession.attached(vm), map)
        .firstWhere((t) => t.name == name);
    final result = await tool.handler(args);
    final text = ((result['content'] as List).first as Map)['text'] as String;
    return jsonDecode(text) as Map<String, dynamic>;
  }

  group('snapshot', () {
    final canned = <String, Map<String, dynamic>>{
      'ext.qa.snapshot': {
        'elements': [
          {'id': 'e1', 'role': 'button', 'label': 'Sign in', 'bounds': {}},
        ],
        'unresolved': [
          {'id': 'u1', 'role': 'tappable', 'bounds': {}},
          {'id': 'u2', 'role': 'tappable', 'bounds': {}},
          {'id': 'u3', 'role': 'tappable', 'bounds': {}},
        ],
      },
    };

    test('by default drops unresolved[] and reports count', () async {
      final result = await call('snapshot', {}, _FakeVm(canned));
      expect(result.containsKey('unresolved'), isFalse,
          reason: 'unresolved array should be hidden by default');
      expect(result['unresolved_count'], 3);
      expect(result['elements'], isA<List>());
    });

    test('include_unresolved:true keeps the full array', () async {
      final result =
          await call('snapshot', {'include_unresolved': true}, _FakeVm(canned));
      expect(result['unresolved'], isA<List>());
      expect((result['unresolved'] as List).length, 3);
      expect(result.containsKey('unresolved_count'), isFalse);
    });
  });

  group('screenshot', () {
    final canned = <String, Map<String, dynamic>>{
      'ext.qa.screenshot': {
        'format': 'png',
        'width': 1,
        'height': 1,
        'data_base64': _onePxPng,
      },
    };

    test('by default writes PNG to disk and returns path, not base64',
        () async {
      final result = await call('screenshot', {}, _FakeVm(canned));
      expect(result.containsKey('data_base64'), isFalse,
          reason: 'base64 should be hidden by default');
      expect(result['path'], isA<String>());
      expect(result['width'], 1);
      expect(result['height'], 1);
      expect(result['size_bytes'], greaterThan(0));
      final f = File(result['path'] as String);
      expect(f.existsSync(), isTrue);
      expect(f.readAsBytesSync().length, result['size_bytes']);
      await f.parent.delete(recursive: true);
    });

    test('return_base64:true returns base64 and no path', () async {
      final result =
          await call('screenshot', {'return_base64': true}, _FakeVm(canned));
      expect(result.containsKey('path'), isFalse);
      expect(result['data_base64'], _onePxPng);
    });
  });
}
