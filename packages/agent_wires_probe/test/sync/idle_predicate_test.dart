import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/sync/idle_predicate.dart';
import 'package:agent_wires_probe/src/sync/http_inflight_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('isIdle returns true after pumpAndSettle on a static screen',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('static'))));
    await tester.pumpAndSettle();
    expect(IdlePredicate.isIdle(), isTrue);
  });

  testWidgets(
      'currentStatus reports in_flight_http and blocked_by when HTTP active',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    await tester.pumpAndSettle();
    final token = HttpInflightTracker.beginRequest();
    try {
      final status = IdlePredicate.currentStatus();
      expect(status.idle, isFalse);
      expect(status.inflightHttp, 1);
      expect(status.blockedBy, contains('in_flight_http:1'));
    } finally {
      HttpInflightTracker.endRequest(token);
    }
  });

  testWidgets(
      'ignoreAnimations:true ignores scheduled frames and transient callbacks',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    await tester.pumpAndSettle();
    // Schedule a frame to simulate an active animation.
    WidgetsBinding.instance.scheduleFrame();
    final strict = IdlePredicate.currentStatus();
    final lenient = IdlePredicate.currentStatus(ignoreAnimations: true);
    expect(strict.idle, isFalse,
        reason: 'with scheduled frame, strict should not be idle');
    expect(lenient.idle, isTrue,
        reason: 'ignoreAnimations should skip the scheduled_frame check');
    expect(lenient.blockedBy, isEmpty);
  });
}
