import 'package:flutter/gestures.dart';

class GestureSynth {
  static int _nextPointer = 1;

  static Future<void> tapAt(Offset position) async {
    final pointer = _nextPointer++;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      position: position,
      timeStamp: Duration.zero,
    ));
    binding.handlePointerEvent(PointerUpEvent(
      pointer: pointer,
      position: position,
      timeStamp: const Duration(milliseconds: 50),
    ));
  }

  static Future<void> longPressAt(Offset position, {Duration hold = const Duration(milliseconds: 600)}) async {
    final pointer = _nextPointer++;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      position: position,
      timeStamp: Duration.zero,
    ));
    await Future<void>.delayed(hold);
    binding.handlePointerEvent(PointerUpEvent(
      pointer: pointer,
      position: position,
      timeStamp: hold + const Duration(milliseconds: 50),
    ));
  }

  static Future<void> swipe(Offset from, Offset to, {Duration duration = const Duration(milliseconds: 300), int steps = 20}) async {
    final pointer = _nextPointer++;
    final binding = GestureBinding.instance;
    final dt = duration ~/ steps;
    binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      position: from,
      timeStamp: Duration.zero,
    ));
    var t = dt;
    for (var i = 1; i <= steps; i++) {
      final frac = i / steps;
      final pos = Offset.lerp(from, to, frac)!;
      binding.handlePointerEvent(PointerMoveEvent(
        pointer: pointer,
        position: pos,
        timeStamp: t,
      ));
      t += dt;
    }
    binding.handlePointerEvent(PointerUpEvent(
      pointer: pointer,
      position: to,
      timeStamp: t,
    ));
  }
}
