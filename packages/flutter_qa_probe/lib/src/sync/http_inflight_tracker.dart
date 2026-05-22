import 'dart:io';

import 'network_log.dart';

/// Tracks in-flight HTTP requests so that [wait_for_idle] can determine when
/// HTTP traffic has settled.
///
/// Call [install] once (it is idempotent) to wrap the global [HttpOverrides].
/// The tracker then intercepts every [HttpClient] created by the app and
/// increments/decrements an atomic counter around each request lifecycle.
class HttpInflightTracker {
  static int _inflight = 0;
  static int _tokens = 0;
  static bool _installed = false;

  /// Number of HTTP requests that have been started but whose response has not
  /// yet been fully consumed.
  static int get inflight => _inflight;

  /// Installs the tracking [HttpOverrides] globally.  Safe to call multiple
  /// times – subsequent calls are no-ops.
  static void install() {
    if (_installed) return;
    _installed = true;
    HttpOverrides.global = _TrackingOverrides(HttpOverrides.current);
  }

  /// Records the start of a new request and returns an opaque token that must
  /// be passed to [endRequest] when the response is consumed.
  static int beginRequest() {
    _inflight++;
    return _tokens++;
  }

  /// Records the end of the request identified by [token].
  static void endRequest(int token) {
    if (_inflight > 0) _inflight--;
  }
}

// ---------------------------------------------------------------------------
// Internal HttpOverrides wrapper
// ---------------------------------------------------------------------------

class _TrackingOverrides extends HttpOverrides {
  _TrackingOverrides(this.inner);
  final HttpOverrides? inner;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client =
        inner?.createHttpClient(context) ?? super.createHttpClient(context);
    return _TrackingClient(client);
  }
}

// ---------------------------------------------------------------------------
// Internal HttpClient wrapper – explicit forwarding, no noSuchMethod
// ---------------------------------------------------------------------------

class _TrackingClient implements HttpClient {
  _TrackingClient(this._inner);
  final HttpClient _inner;

  /// Wraps an [open] call with begin/end tracking around the full request
  /// lifetime, AND records a [NetworkEntry] for `get_network`.
  Future<HttpClientRequest> _track(
      Future<HttpClientRequest> Function() open) async {
    final token = HttpInflightTracker.beginRequest();
    final stopwatch = Stopwatch()..start();
    final startedAt = DateTime.now().toUtc();
    try {
      final req = await open();
      final entry = NetworkEntry(
        method: req.method,
        url: req.uri.toString(),
        startedAt: startedAt.toIso8601String(),
      );
      NetworkLog.add(entry);
      req.done.then((response) {
        stopwatch.stop();
        entry
          ..finishedAt = DateTime.now().toUtc().toIso8601String()
          ..statusCode = response.statusCode
          ..durationMs = stopwatch.elapsedMilliseconds;
      }, onError: (Object error, StackTrace _) {
        stopwatch.stop();
        entry
          ..finishedAt = DateTime.now().toUtc().toIso8601String()
          ..durationMs = stopwatch.elapsedMilliseconds
          ..error = error.toString();
      }).whenComplete(() => HttpInflightTracker.endRequest(token));
      return req;
    } catch (e) {
      HttpInflightTracker.endRequest(token);
      // A failure here means we never got an HttpClientRequest, so we
      // never created a NetworkEntry — that's fine; this path is rare
      // (DNS failures, connection refused before opening).
      rethrow;
    }
  }

  // -------- tracked request methods --------

  @override
  Future<HttpClientRequest> open(
          String method, String host, int port, String path) =>
      _track(() => _inner.open(method, host, port, path));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _track(() => _inner.openUrl(method, url));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _track(() => _inner.get(host, port, path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      _track(() => _inner.getUrl(url));

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _track(() => _inner.post(host, port, path));

  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      _track(() => _inner.postUrl(url));

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _track(() => _inner.put(host, port, path));

  @override
  Future<HttpClientRequest> putUrl(Uri url) =>
      _track(() => _inner.putUrl(url));

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _track(() => _inner.delete(host, port, path));

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      _track(() => _inner.deleteUrl(url));

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _track(() => _inner.patch(host, port, path));

  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      _track(() => _inner.patchUrl(url));

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _track(() => _inner.head(host, port, path));

  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      _track(() => _inner.headUrl(url));

  // -------- pass-through properties --------

  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool v) => _inner.autoUncompress = v;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _inner.connectionTimeout = v;

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration v) => _inner.idleTimeout = v;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _inner.maxConnectionsPerHost = v;

  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? v) => _inner.userAgent = v;

  // -------- pass-through methods --------

  @override
  void addCredentials(
          Uri url, String realm, HttpClientCredentials credentials) =>
      _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(String host, int port, String realm,
          HttpClientCredentials credentials) =>
      _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(
          Future<bool> Function(Uri url, String scheme, String? realm)? f) =>
      _inner.authenticate = f;

  @override
  set authenticateProxy(
          Future<bool> Function(
                  String host, int port, String scheme, String? realm)?
              f) =>
      _inner.authenticateProxy = f;

  @override
  set badCertificateCallback(
          bool Function(X509Certificate cert, String host, int port)?
              callback) =>
      _inner.badCertificateCallback = callback;

  @override
  set connectionFactory(
          Future<ConnectionTask<Socket>> Function(
                  Uri url, String? proxyHost, int? proxyPort)?
              f) =>
      _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
