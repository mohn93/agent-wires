import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'extensions/clear_text_ext.dart';
import 'extensions/enter_text_ext.dart';
import 'extensions/get_logs_ext.dart';
import 'extensions/get_network_ext.dart';
import 'extensions/inspect_ext.dart';
import 'extensions/long_press_ext.dart';
import 'extensions/press_back_ext.dart';
import 'extensions/screenshot_ext.dart';
import 'extensions/snapshot_ext.dart';
import 'extensions/scroll_ext.dart';
import 'extensions/swipe_ext.dart';
import 'extensions/tap_ext.dart';
import 'extensions/wait_for_element_ext.dart';
import 'extensions/wait_for_idle_ext.dart';
import 'extensions/wait_for_route_ext.dart';
import 'logs/log_buffer.dart';
import 'logs/log_capture.dart';
import 'navigation/route_tracker.dart';
import 'sync/http_inflight_tracker.dart';

class AgentWiresProbe {
  AgentWiresProbe._();

  static bool _installed = false;
  static final Set<String> _registered = <String>{};

  static final RouteTracker _routeTracker = RouteTracker();
  static RouteTracker get routeTracker => _routeTracker;

  static final LogBuffer _logBuffer = LogBuffer();
  static LogBuffer get logBuffer => _logBuffer;

  static bool get isInstalled => _installed;
  static Set<String> get registeredExtensions => Set.unmodifiable(_registered);

  static void install() {
    if (_installed) return;
    if (kReleaseMode) return;
    _installed = true;
    HttpInflightTracker.install();
    LogCapture.install(_logBuffer);
    GetLogsExtension.bind(_logBuffer);
    _register('ext.qa.ping', (_, __) async {
      return developer.ServiceExtensionResponse.result('{"ok":true}');
    });
    _register(SnapshotExtension.name, SnapshotExtension.handle);
    _register(InspectExtension.name, InspectExtension.handle);
    _register(ScreenshotExtension.name, ScreenshotExtension.handle);
    _register(TapExtension.name, TapExtension.handle);
    _register(LongPressExtension.name, LongPressExtension.handle);
    _register(SwipeExtension.name, SwipeExtension.handle);
    _register(EnterTextExtension.name, EnterTextExtension.handle);
    _register(ClearTextExtension.name, ClearTextExtension.handle);
    _register(ScrollExtension.name, ScrollExtension.handle);
    _register(PressBackExtension.name, PressBackExtension.handle);
    _register(WaitForElementExtension.name, WaitForElementExtension.handle);
    _register(WaitForIdleExtension.name, WaitForIdleExtension.handle);
    _register(WaitForRouteExtension.name, WaitForRouteExtension.handle);
    _register(GetLogsExtension.name, GetLogsExtension.handle);
    _register(GetNetworkExtension.name, GetNetworkExtension.handle);
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
