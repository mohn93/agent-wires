import 'package:flutter/painting.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = ActionOverlayController.instance;
  setUp(c.reset);

  test('defaults: enabled, no effects, not suppressed', () {
    expect(c.enabled, isTrue);
    expect(c.effects, isEmpty);
    expect(c.suppressedForCapture, isFalse);
  });

  test('showTap adds a TapEffect at the point', () {
    c.showTap(const Offset(3, 4));
    expect(c.effects.single, isA<TapEffect>());
    expect((c.effects.single as TapEffect).point, const Offset(3, 4));
  });

  test('pushes are no-ops while disabled', () {
    c.setEnabled(false);
    c.showTap(Offset.zero);
    c.showFlash(kind: OverlayFlashKind.snapshot);
    expect(c.effects, isEmpty);
  });

  test('setEnabled(false) clears existing effects', () {
    c.showTap(Offset.zero);
    expect(c.effects, isNotEmpty);
    c.setEnabled(false);
    expect(c.effects, isEmpty);
  });

  test('the concurrent cap drops the oldest', () {
    for (var i = 0; i < ActionOverlayController.maxEffects + 3; i++) {
      c.showTap(Offset(i.toDouble(), 0));
    }
    expect(c.effects.length, ActionOverlayController.maxEffects);
    // oldest (x=0,1,2) dropped; first remaining is x=3.
    expect((c.effects.first as TapEffect).point.dx, 3);
  });

  test('suppression hides visibleEffects but keeps effects', () {
    c.showTap(Offset.zero);
    c.beginCaptureSuppression();
    expect(c.suppressedForCapture, isTrue);
    expect(c.visibleEffects, isEmpty);
    expect(c.effects, isNotEmpty);
    c.endCaptureSuppression();
    expect(c.visibleEffects, isNotEmpty);
  });

  test('removeEffect removes a specific effect', () {
    c.showTap(Offset.zero);
    final fx = c.effects.single;
    c.removeEffect(fx);
    expect(c.effects, isEmpty);
  });

  test('notifies listeners on change', () {
    var n = 0;
    void listener() => n++;
    c.addListener(listener);
    c.showTap(Offset.zero);
    c.removeListener(listener);
    expect(n, greaterThan(0));
  });
}
