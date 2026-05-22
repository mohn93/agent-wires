/// One observed HTTP exchange. Lifecycle:
/// 1. Created when [HttpClient.open*] completes successfully — we have a
///    method, url, and started-at timestamp.
/// 2. Finalised when `HttpClientRequest.done` resolves — we add status,
///    duration, and (on failure) an error.
///
/// Captured by [NetworkLog] from inside the probe's existing
/// HttpOverrides wrapper. Visible to the agent via `ext.qa.get_network`.
class NetworkEntry {
  NetworkEntry({
    required this.method,
    required this.url,
    required this.startedAt,
  });

  final String method;
  final String url;
  final String startedAt;

  String? finishedAt;
  int? statusCode;
  int? durationMs;
  String? error;

  bool get pending => finishedAt == null && error == null;

  Map<String, dynamic> toJson() => {
        'method': method,
        'url': url,
        'started_at': startedAt,
        if (finishedAt != null) 'finished_at': finishedAt,
        if (statusCode != null) 'status_code': statusCode,
        if (durationMs != null) 'duration_ms': durationMs,
        if (error != null) 'error': error,
        if (pending) 'pending': true,
      };
}

/// Bounded ring buffer of HTTP exchanges. The agent polls `get_network`
/// with a `since` cursor to drain new entries since the last action.
class NetworkLog {
  NetworkLog._();

  static const int _capacity = 200;
  static final List<NetworkEntry> _entries = <NetworkEntry>[];

  static void add(NetworkEntry entry) {
    _entries.add(entry);
    while (_entries.length > _capacity) {
      _entries.removeAt(0);
    }
  }

  /// Returns entries whose `started_at` is strictly after [since],
  /// capped at [limit]. If [since] is null, returns the most recent
  /// [limit] entries (in chronological order).
  static List<NetworkEntry> query({String? since, int limit = 100}) {
    Iterable<NetworkEntry> view = _entries;
    if (since != null) {
      view = view.where((e) => e.startedAt.compareTo(since) > 0);
    }
    final list = view.toList();
    if (list.length > limit) {
      return list.sublist(list.length - limit);
    }
    return list;
  }

  static int get length => _entries.length;
  static void clear() => _entries.clear();
}
