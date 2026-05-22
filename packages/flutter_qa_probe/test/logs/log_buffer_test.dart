import 'package:flutter_qa_probe/src/logs/log_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('query with no since returns the most recent up to limit', () {
    final buf = LogBuffer(capacity: 100);
    for (var i = 0; i < 5; i++) {
      buf.add(_entry(i));
    }
    final out = buf.query(limit: 3);
    expect(out.map((e) => e.message), ['msg-2', 'msg-3', 'msg-4']);
  });

  test('query with since returns only newer entries (exclusive)', () {
    final buf = LogBuffer(capacity: 100);
    for (var i = 0; i < 5; i++) {
      buf.add(_entry(i));
    }
    // since = timestamp of msg-2 → expect msg-3 and msg-4 only.
    final out = buf.query(since: '2026-05-01T00:00:02Z', limit: 100);
    expect(out.map((e) => e.message), ['msg-3', 'msg-4']);
  });

  test('capacity-bounded: old entries get evicted', () {
    final buf = LogBuffer(capacity: 3);
    for (var i = 0; i < 5; i++) {
      buf.add(_entry(i));
    }
    expect(buf.length, 3);
    // Surviving entries are the last 3.
    expect(buf.query(limit: 10).map((e) => e.message),
        ['msg-2', 'msg-3', 'msg-4']);
  });
}

LogEntry _entry(int i) => LogEntry(
      // Lexicographic order matches numeric order for these values.
      timestamp: '2026-05-01T00:00:0${i}Z',
      level: 'debug',
      message: 'msg-$i',
    );
