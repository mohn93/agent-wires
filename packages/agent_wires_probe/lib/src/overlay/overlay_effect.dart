import 'package:flutter/painting.dart';

/// Whole-screen perception events that get a brief flash.
enum OverlayFlashKind { screenshot, snapshot }

/// One transient on-screen effect drawn for a human watching the agent drive
/// the app. Self-describing geometry + an animation duration; the host owns
/// the animation and removes the effect when it completes.
sealed class OverlayEffect {
  OverlayEffect({required this.id, required this.duration});
  final String id;
  final Duration duration;
}

class TapEffect extends OverlayEffect {
  TapEffect({required super.id, required this.point, this.longPress = false})
      : super(duration: const Duration(milliseconds: 600));
  final Offset point;
  final bool longPress;
}

class DragEffect extends OverlayEffect {
  DragEffect({required super.id, required this.from, required this.to})
      : super(duration: const Duration(milliseconds: 800));
  final Offset from;
  final Offset to;
}

class HighlightEffect extends OverlayEffect {
  HighlightEffect({required super.id, required this.bounds, this.label})
      : super(duration: const Duration(milliseconds: 1000));
  final Rect bounds;
  final String? label;
}

class FlashEffect extends OverlayEffect {
  FlashEffect({required super.id, required this.kind})
      : super(duration: const Duration(milliseconds: 300));
  final OverlayFlashKind kind;
}
