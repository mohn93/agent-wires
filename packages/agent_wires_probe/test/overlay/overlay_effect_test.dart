import 'package:flutter/painting.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TapEffect carries its point, longPress flag and a 600ms duration', () {
    final fx = TapEffect(id: 'a', point: const Offset(10, 20), longPress: true);
    expect(fx.point, const Offset(10, 20));
    expect(fx.longPress, isTrue);
    expect(fx.duration, const Duration(milliseconds: 600));
  });

  test('DragEffect carries from/to', () {
    final fx = DragEffect(id: 'b', from: Offset.zero, to: const Offset(5, 5));
    expect(fx.from, Offset.zero);
    expect(fx.to, const Offset(5, 5));
  });

  test('HighlightEffect carries bounds and optional label', () {
    final fx = HighlightEffect(
        id: 'c', bounds: const Rect.fromLTWH(0, 0, 30, 40), label: 'Submit');
    expect(fx.bounds.width, 30);
    expect(fx.label, 'Submit');
  });

  test('FlashEffect carries its kind', () {
    final fx = FlashEffect(id: 'd', kind: OverlayFlashKind.screenshot);
    expect(fx.kind, OverlayFlashKind.screenshot);
  });
}
