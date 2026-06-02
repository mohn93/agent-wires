import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/screenshot_ext.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_installer.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = ActionOverlayController.instance;
  setUp(c.reset);
  tearDown(() {
    c.reset();
    ActionOverlayInstaller.reset();
  });

  testWidgets(
      'an effect still on screen is painted out before the capture body runs',
      (tester) async {
    // Regression for the leak where a still-animating effect from a preceding
    // action ends up baked into the screenshot. The overlay must be committed
    // empty before `toImage` rasterizes the layer tree.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox.expand()),
    ));
    ActionOverlayInstaller.ensureInstalled();
    c.showFlash(kind: OverlayFlashKind.snapshot); // first effect -> fx_0
    await tester.pump(); // host paints the flash
    expect(find.byKey(const ValueKey('aw_effect_fx_0')), findsOneWidget,
        reason: 'effect should be on screen before the capture');

    var effectPresentDuringBody = true;
    final fut = ScreenshotExtension.captureWithOverlaySuppressed(() async {
      effectPresentDuringBody =
          find.byKey(const ValueKey('aw_effect_fx_0')).evaluate().isNotEmpty;
      return 0;
    });
    await tester.pump(); // drives the scheduled frame so endOfFrame resolves
    await fut;

    expect(effectPresentDuringBody, isFalse,
        reason: 'the overlay must be painted out before the body rasterizes');
  });

  testWidgets('suppression flag is set during the body and cleared after',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    var suppressedDuring = false;
    final fut = ScreenshotExtension.captureWithOverlaySuppressed(() async {
      suppressedDuring = c.suppressedForCapture;
      return 42;
    });
    await tester.pump();
    final result = await fut;
    expect(result, 42);
    expect(suppressedDuring, isTrue);
    expect(c.suppressedForCapture, isFalse);
  });

  testWidgets('suppression is restored even if the body throws',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    final fut = ScreenshotExtension.captureWithOverlaySuppressed<void>(
        () async => throw StateError('boom'));
    // Attach the expectation before pumping so the rejection (which lands while
    // the scheduled frame is driven) is handled, not an unhandled async error.
    final expectation = expectLater(fut, throwsStateError);
    await tester.pump();
    await expectation;
    expect(c.suppressedForCapture, isFalse);
  });
}
