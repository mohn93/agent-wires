import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'log_buffer.dart';

/// Tees runtime log signals into a [LogBuffer] without preventing them from
/// reaching their normal sinks (the IDE debug console, crash reporters, …).
///
/// Capture surfaces:
///
/// 1. `debugPrint` — Flutter's framework convention; covers anything the
///    framework prints plus user code that calls debugPrint directly.
/// 2. `FlutterError.onError` — uncaught framework / widget errors.
/// 3. `PlatformDispatcher.instance.onError` — uncaught zone-level async errors.
///
/// Plain `print()` is NOT captured because there is no in-process API to
/// override it without forking a zone above the entire app. Apps that want
/// that coverage can wrap their `runApp` in `runZonedGuarded` and route
/// `zoneSpecification.print` into [LogCapture.append].
class LogCapture {
  LogCapture._();

  static LogBuffer? _buffer;
  static bool _installed = false;
  static DebugPrintCallback? _originalDebugPrint;
  static FlutterExceptionHandler? _originalFlutterOnError;
  static bool Function(Object error, StackTrace stack)? _originalPlatformOnError;

  /// Connects the capture hooks to [buffer]. Hook installation is one-shot;
  /// subsequent calls only rebind the destination buffer (useful in tests
  /// that want a fresh buffer per case while the global hooks stay live).
  static void install(LogBuffer buffer) {
    _buffer = buffer;
    if (_installed) return;
    _installed = true;

    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
      if (message != null && message.isNotEmpty) {
        append(level: 'debug', message: message);
      }
    };

    _originalFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _originalFlutterOnError?.call(details);
      append(
        level: 'error',
        message: details.exceptionAsString(),
        loggerName: 'FlutterError',
        error: details.exception.toString(),
        stack: details.stack?.toString(),
      );
    };

    _originalPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      final handled = _originalPlatformOnError?.call(error, stack) ?? false;
      append(
        level: 'error',
        message: error.toString(),
        loggerName: 'PlatformDispatcher',
        error: error.toString(),
        stack: stack.toString(),
      );
      return handled;
    };
  }

  /// Direct insertion point for callers who want to forward their own log
  /// streams into the probe — e.g. wrapping `runZonedGuarded` to catch raw
  /// `print` calls, or adapting `package:logging` records.
  static void append({
    required String level,
    required String message,
    String? loggerName,
    String? error,
    String? stack,
  }) {
    final buf = _buffer;
    if (buf == null) return;
    buf.add(LogEntry(
      timestamp: DateTime.now().toUtc().toIso8601String(),
      level: level,
      message: message,
      loggerName: loggerName,
      error: error,
      stack: stack,
    ));
  }
}
