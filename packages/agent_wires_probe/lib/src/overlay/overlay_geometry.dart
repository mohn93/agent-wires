import 'package:flutter/widgets.dart';

/// Logical size of the app's primary view, for effects that have no element to
/// anchor to (scroll, press_back). Falls back to a sane default before a view
/// is available.
Size currentScreenSize() {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) return const Size(400, 800);
  return view.physicalSize / view.devicePixelRatio;
}

/// Unit vector for a named scroll/back direction in screen space.
Offset directionVector(String direction) => switch (direction) {
      'up' => const Offset(0, -1),
      'down' => const Offset(0, 1),
      'left' => const Offset(-1, 0),
      'right' => const Offset(1, 0),
      _ => Offset.zero,
    };
