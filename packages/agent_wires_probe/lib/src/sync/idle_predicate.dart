import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'http_inflight_tracker.dart';

/// Snapshot of which "idle" criteria are currently satisfied.
///
/// `idle` is true when **every** check the caller cares about passes.
/// `blockedBy` is the human-readable list of criteria that did NOT pass —
/// surfaced to the agent on timeout so it knows *why* the app never settled
/// (e.g. continuous animations on a Slider screen).
class IdleStatus {
  IdleStatus({
    required this.hasScheduledFrame,
    required this.inTransientCallback,
    required this.inflightHttp,
    required this.ignoreAnimations,
  });

  final bool hasScheduledFrame;
  final bool inTransientCallback;
  final int inflightHttp;
  final bool ignoreAnimations;

  bool get idle {
    if (inflightHttp > 0) return false;
    if (ignoreAnimations) return true;
    if (hasScheduledFrame) return false;
    if (inTransientCallback) return false;
    return true;
  }

  List<String> get blockedBy {
    final reasons = <String>[];
    if (inflightHttp > 0) reasons.add('in_flight_http:$inflightHttp');
    if (!ignoreAnimations) {
      if (hasScheduledFrame) reasons.add('scheduled_frame');
      if (inTransientCallback) reasons.add('transient_callback');
    }
    return reasons;
  }

  Map<String, dynamic> toJson() => {
        'idle': idle,
        if (!idle) 'blocked_by': blockedBy,
        'in_flight_http': inflightHttp,
        'has_scheduled_frame': hasScheduledFrame,
        'in_transient_callback': inTransientCallback,
        if (ignoreAnimations) 'ignore_animations': true,
      };
}

/// Predicate that determines whether the Flutter app is in an idle state.
///
/// An app is considered idle when:
/// 1. No frames are scheduled
/// 2. No animations/transient callbacks are active
/// 3. No HTTP requests are in flight
///
/// Pass `ignoreAnimations: true` to skip checks (1) and (2) — useful on
/// screens with continuous spring animations or hint-chip fades that never
/// settle (the agent flagged this as a real blocker).
class IdlePredicate {
  /// Captures the current idle status without waiting.
  static IdleStatus currentStatus({bool ignoreAnimations = false}) {
    final scheduler = SchedulerBinding.instance;
    return IdleStatus(
      hasScheduledFrame: scheduler.hasScheduledFrame,
      inTransientCallback: scheduler.schedulerPhase != SchedulerPhase.idle,
      inflightHttp: HttpInflightTracker.inflight,
      ignoreAnimations: ignoreAnimations,
    );
  }

  /// Returns true if the app is in an idle state, false otherwise.
  ///
  /// Kept for backwards compatibility; prefer [currentStatus] when you need
  /// to know *why* the app is not idle.
  static bool isIdle({bool ignoreAnimations = false}) =>
      currentStatus(ignoreAnimations: ignoreAnimations).idle;

  /// Polls until the app is idle OR `timeout` elapses. On timeout, returns
  /// the final non-idle [IdleStatus] so the caller can surface `blockedBy`.
  static Future<IdleStatus> waitUntilIdle({
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 50),
    bool ignoreAnimations = false,
  }) async {
    final deadline = DateTime.now().add(timeout);
    IdleStatus latest = currentStatus(ignoreAnimations: ignoreAnimations);
    while (DateTime.now().isBefore(deadline)) {
      latest = currentStatus(ignoreAnimations: ignoreAnimations);
      if (latest.idle) return latest;
      await Future<void>.delayed(interval);
      WidgetsBinding.instance.scheduleFrame();
    }
    return latest;
  }
}
