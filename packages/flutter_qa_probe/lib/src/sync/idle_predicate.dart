import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'http_inflight_tracker.dart';

/// Predicate that determines whether the Flutter app is in an idle state.
///
/// An app is considered idle when:
/// 1. No frames are scheduled
/// 2. No animations/transient callbacks are active
/// 3. No HTTP requests are in flight
class IdlePredicate {
  /// Returns true if the app is in an idle state, false otherwise.
  static bool isIdle() {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.hasScheduledFrame) return false;
    if (scheduler.schedulerPhase != SchedulerPhase.idle) return false;
    if (HttpInflightTracker.inflight > 0) return false;
    return true;
  }

  /// Polls `isIdle` until it returns true OR `timeout` elapses.
  ///
  /// Returns true if the app became idle before the timeout, false otherwise.
  static Future<bool> waitUntilIdle({
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 50),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (isIdle()) return true;
      await Future<void>.delayed(interval);
      WidgetsBinding.instance.scheduleFrame();
    }
    return isIdle();
  }
}
