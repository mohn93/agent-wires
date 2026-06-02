import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/screenshot_ext.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = ActionOverlayController.instance;
  setUp(c.reset);
  tearDown(c.reset);

  testWidgets('overlay is suppressed during the body, restored after',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    bool wasSuppressedDuring = false;
    final result = await ScreenshotExtension.captureWithOverlaySuppressed(
        () async {
      wasSuppressedDuring = c.suppressedForCapture;
      return 42;
    });
    expect(result, 42);
    expect(wasSuppressedDuring, isTrue);
    expect(c.suppressedForCapture, isFalse);
  });

  testWidgets('suppression is restored even if the body throws',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    await expectLater(
      ScreenshotExtension.captureWithOverlaySuppressed<void>(
          () async => throw StateError('boom')),
      throwsStateError,
    );
    expect(c.suppressedForCapture, isFalse);
  });
}
