import 'dart:io';
import 'package:flutter_probe/src/sync/http_inflight_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counter tracks begin/end token pairs', () async {
    HttpInflightTracker.install();
    expect(HttpInflightTracker.inflight, 0);

    final token = HttpInflightTracker.beginRequest();
    expect(HttpInflightTracker.inflight, 1);
    HttpInflightTracker.endRequest(token);
    expect(HttpInflightTracker.inflight, 0);
  });

  test('install is idempotent', () {
    HttpInflightTracker.install();
    HttpInflightTracker.install();
    expect(HttpOverrides.current, isNotNull);
  });
}
