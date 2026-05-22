import 'package:flutter_qa_probe/src/sync/network_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(NetworkLog.clear);

  test('query returns most recent up to limit', () {
    for (var i = 0; i < 5; i++) {
      NetworkLog.add(NetworkEntry(
        method: 'GET',
        url: 'https://api.example/$i',
        startedAt: '2026-05-22T00:00:0${i}Z',
      ));
    }
    final out = NetworkLog.query(limit: 3);
    expect(out.map((e) => e.url),
        ['https://api.example/2', 'https://api.example/3', 'https://api.example/4']);
  });

  test('query honors since (exclusive)', () {
    for (var i = 0; i < 4; i++) {
      NetworkLog.add(NetworkEntry(
        method: 'GET',
        url: 'https://x/$i',
        startedAt: '2026-05-22T00:00:0${i}Z',
      ));
    }
    final out = NetworkLog.query(since: '2026-05-22T00:00:01Z', limit: 10);
    expect(out.map((e) => e.url), ['https://x/2', 'https://x/3']);
  });

  test('toJson includes finished fields when set, pending flag otherwise',
      () {
    final e = NetworkEntry(
      method: 'POST',
      url: 'https://api/login',
      startedAt: '2026-05-22T00:00:00Z',
    );
    expect(e.toJson()['pending'], true);

    e
      ..finishedAt = '2026-05-22T00:00:01Z'
      ..statusCode = 200
      ..durationMs = 1000;
    final j = e.toJson();
    expect(j.containsKey('pending'), isFalse);
    expect(j['status_code'], 200);
    expect(j['duration_ms'], 1000);
  });
}
