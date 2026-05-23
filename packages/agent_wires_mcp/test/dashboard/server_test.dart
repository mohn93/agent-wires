// packages/agent_wires_mcp/test/dashboard/server_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:agent_wires_mcp/src/dashboard/server.dart';
import 'package:agent_wires_mcp/src/map/map_record.dart';
import 'package:agent_wires_mcp/src/map/semantic_map.dart';
import 'package:test/test.dart';

void main() {
  late DashboardServer server;
  late SemanticMap map;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dashboard_test_');
    map = SemanticMap(projectRoot: tmp.path);
    map.upsert(MapEntry(fingerprint: 'f_1', humanLabel: 'Checkout'));
    server = DashboardServer(map: map);
    await server.start(port: 0);  // 0 = OS-assigned
  });

  tearDown(() async {
    await server.stop();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('GET /api/labels returns persisted labels', () async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('http://localhost:${server.port}/api/labels'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final parsed = jsonDecode(body) as Map<String, dynamic>;
    expect(parsed['labels'], isA<List>());
    expect((parsed['labels'] as List).first['human_label'], 'Checkout');
    client.close();
  });

  test('GET /api/unresolved returns entries with no human_label', () async {
    map.upsert(MapEntry(fingerprint: 'f_2'));  // unresolved
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('http://localhost:${server.port}/api/unresolved'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final parsed = jsonDecode(body) as Map<String, dynamic>;
    final unresolved = parsed['unresolved'] as List;
    expect(unresolved.any((e) => (e as Map)['fingerprint'] == 'f_2'), isTrue);
    expect(unresolved.any((e) => (e as Map)['fingerprint'] == 'f_1'), isFalse);
    client.close();
  });

  test('POST /api/label persists a label', () async {
    final client = HttpClient();
    final req = await client.postUrl(Uri.parse('http://localhost:${server.port}/api/label'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'fingerprint': 'f_new', 'name': 'New Label'}));
    final resp = await req.close();
    expect(resp.statusCode, 200);
    expect(map.get('f_new')?.humanLabel, 'New Label');
    client.close();
  });

  test('POST /api/dismiss marks an entry dismissed', () async {
    final client = HttpClient();
    final req = await client.postUrl(Uri.parse('http://localhost:${server.port}/api/dismiss'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'fingerprint': 'f_1'}));
    final resp = await req.close();
    expect(resp.statusCode, 200);
    expect(map.get('f_1')?.dismissed, isTrue);
    client.close();
  });

  test('GET / returns HTML', () async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('http://localhost:${server.port}/'));
    final resp = await req.close();
    expect(resp.statusCode, 200);
    expect(resp.headers.contentType?.mimeType, 'text/html');
    client.close();
  });

  test('GET /api/unresolved returns entries sorted descending by observation_count', () async {
    map.upsert(MapEntry(fingerprint: 'u_low', observationCount: 1));
    map.upsert(MapEntry(fingerprint: 'u_high', observationCount: 5));
    map.upsert(MapEntry(fingerprint: 'u_mid', observationCount: 3));

    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('http://localhost:${server.port}/api/unresolved'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final parsed = jsonDecode(body) as Map<String, dynamic>;
    final unresolved = (parsed['unresolved'] as List)
        .cast<Map<String, dynamic>>()
        .where((e) => (e['fingerprint'] as String).startsWith('u_'))
        .toList();
    expect(unresolved.length, 3);
    expect(unresolved[0]['fingerprint'], 'u_high');
    expect(unresolved[1]['fingerprint'], 'u_mid');
    expect(unresolved[2]['fingerprint'], 'u_low');
    client.close();
  });
}
