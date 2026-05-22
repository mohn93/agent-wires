/// Bounded ring buffer of log entries. Append is O(1); reads filter by
/// timestamp. Lives in the probe so it survives across snapshots and
/// drains incrementally — the MCP server polls `get_logs(since: ...)` and
/// only receives entries it hasn't seen.
class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.loggerName,
    this.error,
    this.stack,
  });

  /// UTC ISO-8601 string. Stable across calls, used as the `since` cursor.
  final String timestamp;

  /// 'debug', 'info', 'warn', 'error'.
  final String level;
  final String message;
  final String? loggerName;
  final String? error;
  final String? stack;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'level': level,
        'message': message,
        if (loggerName != null) 'logger_name': loggerName,
        if (error != null) 'error': error,
        if (stack != null) 'stack': stack,
      };
}

class LogBuffer {
  LogBuffer({this.capacity = 500});
  final int capacity;
  final List<LogEntry> _entries = <LogEntry>[];

  void add(LogEntry entry) {
    _entries.add(entry);
    // Trim from the front when we cross capacity. The buffer is small
    // (default 500) so list.removeAt is fine; if this ever becomes hot
    // path, swap to a circular array.
    while (_entries.length > capacity) {
      _entries.removeAt(0);
    }
  }

  /// Returns entries strictly after [since] (exclusive), capped at [limit].
  /// If [since] is null, returns the most recent [limit] entries.
  List<LogEntry> query({String? since, int limit = 200}) {
    Iterable<LogEntry> view = _entries;
    if (since != null) {
      view = view.where((e) => e.timestamp.compareTo(since) > 0);
    }
    final list = view.toList();
    if (list.length > limit) {
      return list.sublist(list.length - limit);
    }
    return list;
  }

  int get length => _entries.length;
  void clear() => _entries.clear();
}
