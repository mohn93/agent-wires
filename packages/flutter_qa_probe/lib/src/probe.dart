import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'extensions/inspect_ext.dart';
import 'extensions/long_press_ext.dart';
import 'extensions/screenshot_ext.dart';
import 'extensions/snapshot_ext.dart';
import 'extensions/tap_ext.dart';
import 'navigation/route_tracker.dart';

class FlutterQAProbe {
  FlutterQAProbe._();

  static bool _installed = false;
  static final Set<String> _registered = <String>{};

  static final RouteTracker _routeTracker = RouteTracker();
  static RouteTracker get routeTracker => _routeTracker;

  static bool get isInstalled => _installed;
  static Set<String> get registeredExtensions => Set.unmodifiable(_registered);

  static void install() {
    if (_installed) return;
    if (kReleaseMode) return;
    _installed = true;
    _register('ext.qa.ping', (_, __) async {
      return developer.ServiceExtensionResponse.result('{"ok":true}');
    });
    _register(SnapshotExtension.name, SnapshotExtension.handle);
    _register(InspectExtension.name, InspectExtension.handle);
    _register(ScreenshotExtension.name, ScreenshotExtension.handle);
    _register(TapExtension.name, TapExtension.handle);
    _register(LongPressExtension.name, LongPressExtension.handle);
  }

  static void _register(
    String name,
    Future<developer.ServiceExtensionResponse> Function(
      String method, Map<String, String> params,
    ) handler,
  ) {
    developer.registerExtension(name, handler);
    _registered.add(name);
  }
}
