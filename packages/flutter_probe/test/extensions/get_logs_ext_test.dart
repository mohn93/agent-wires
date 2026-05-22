import 'dart:convert';

import 'package:flutter_probe/src/extensions/get_logs_ext.dart';
import 'package:flutter_probe/src/logs/log_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns recent entries with limit + cursor', () async {
    final buf = LogBuffer();
    for (var i = 0; i < 4; i++) {
      buf.add(LogEntry(
        timestamp: '2026-05-22T00:00:0${i}Z',
        level: 'debug',
        message: 'msg-$i',
      ));
    }
    GetLogsExtension.bind(buf);

    final resp = await GetLogsExtension.handle('ext.qa.get_logs', {
      'limit': '2',
    });
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;

    expect(body['count'], 2);
    expect((body['entries'] as List).map((e) => (e as Map)['message']),
        ['msg-2', 'msg-3']);
    expect(body['cursor'], '2026-05-22T00:00:03Z');
  });

  test('honors since to drain incrementally', () async {
    final buf = LogBuffer();
    for (var i = 0; i < 4; i++) {
      buf.add(LogEntry(
        timestamp: '2026-05-22T00:00:0${i}Z',
        level: 'debug',
        message: 'msg-$i',
      ));
    }
    GetLogsExtension.bind(buf);

    final resp = await GetLogsExtension.handle('ext.qa.get_logs', {
      'since': '2026-05-22T00:00:01Z',
    });
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;

    expect((body['entries'] as List).map((e) => (e as Map)['message']),
        ['msg-2', 'msg-3']);
  });
}
