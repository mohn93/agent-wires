# Changelog

## 0.1.0

Initial public release.

- VM-service extensions for an LLM agent to introspect and drive a running
  Flutter app: `ext.qa.snapshot`, `inspect`, `screenshot`, `tap`,
  `long_press`, `swipe`, `enter_text`, `clear_text`, `scroll`,
  `press_back`, `wait_for_idle`, `wait_for_route`, `wait_for_element`,
  `get_logs`, `get_network`, `ping`.
- Denoised semantic tree: a typical 800-node tree collapses to ~15–30
  agent-targetable elements via a three-pass classify / dedup / label
  pipeline.
- Multi-Text label inference — invoice cards, list rows, and other
  multi-text containers get a label that distinguishes one card from
  the next (e.g. `"Sub Total · 9,709.50 LYD · Unpaid · 342844"`).
- Multi-navigator route tracking — `routeStack` surfaces every observed
  navigator's top route so tab apps (AutoRoute, nested Navigators) can
  be told apart.
- HTTP capture — `get_network` returns method / url / status / duration
  per exchange, drained incrementally via a `since` cursor.
- Log capture — `get_logs` tees `debugPrint`, `FlutterError.onError`,
  and `PlatformDispatcher.onError` into a 500-entry ring buffer.
- No-op in `kReleaseMode`; the probe never ships to your users.
