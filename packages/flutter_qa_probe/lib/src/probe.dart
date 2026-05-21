import 'package:flutter/foundation.dart';

class FlutterQAProbe {
  FlutterQAProbe._();

  static bool _installed = false;
  static bool get isInstalled => _installed;

  static void install() {
    if (_installed) return;
    if (kReleaseMode) return; // hard no-op in release builds
    _installed = true;
  }
}
