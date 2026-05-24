# Changelog

## 0.1.3

Post-launch iteration driven by real LLM-agent driving sessions. No
breaking API changes; the public `AgentWiresProbe.install()` /
`AgentWiresProbe.routeTracker.createObserver()` shape is unchanged.

### Snapshot — route-aware and state-aware

- **Route scoping (the big one).** Pushed routes don't unmount what's
  beneath them — Flutter keeps lower pages alive for the back-swipe
  parallax. The walker previously enumerated every layout-active
  element, so a snapshot of `DomainDetailsRoute` would include the home
  screen's FAB, stats cards, and bottom nav (shifted left ~146px by
  parallax but still in the tree). Now per-`Navigator` overlay
  introspection drops any entry buried under a topmost
  viewport-covering page. Covering is judged by **containment** of the
  owning theater's box (not the global window), so `device_preview`
  and nested navigators are scoped against their real viewport.
- **Widget state in the snapshot.** Each element gains an optional
  `state` field: `"on"` / `"off"` for Switch / SwitchListTile /
  CupertinoSwitch; `"checked"` / `"unchecked"` / `"indeterminate"` for
  Checkbox / CheckboxListTile; `"selected"` / `"unselected"` for
  Radio / RadioListTile; the value for Slider / RangeSlider. A
  post-pass hoists state from a contained child to the smallest
  containing labelled parent, so a labelled `SwitchListTile` reports
  `state: "on"` directly without the agent inspecting the inner Switch.
- **Compact by default.** `unresolved[]` is now omitted and replaced by
  `unresolved_count` unless the MCP caller passes `include_unresolved:
  true` — cuts snapshot size by ~60% on real screens.
- **Diagnostics.** Snapshot output gains an optional `_debug.occlusion`
  block: `{theaters_found, entries_processed, entries_dropped,
  viewport_found, theaters: [...]}`. Lets the agent verify the
  route-scoping pass ran and (when it didn't drop anything) see per-
  theater entry descriptions so the failure mode is debuggable
  without instrumenting the probe.

### inspect — drill into custom widgets

- **Descendants subtree.** `ext.qa.inspect` now returns a
  `descendants[]` array with `{depth, widget_type, visible_text?}` for
  every element up to `descendant_depth` (default 3, capped at 500
  entries). Lets the agent answer "what's inside this Card?" without
  re-snapshotting.
- **`CustomPaint` metadata.** Descendant entries for `CustomPaint`
  surface `painter` (the painter's runtime type, e.g.
  `"PrecisionReactiveSliderPainter"`), `foreground_painter` if set,
  and rendered `size`. Tells the agent "this region is drawn pixels,
  not addressable widgets" — the integrator can wrap with
  `Semantics(button: true, label: '…')` or attach a `Key` to make it
  targetable. README has an integrator note covering this.

### Sync — diagnose stuck idles

- `ext.qa.wait_for_idle` returns a structured `IdleStatus` JSON:
  `{idle, blocked_by, in_flight_http, has_scheduled_frame,
  in_transient_callback}`. On timeout, `blocked_by` lists what's still
  active (`scheduled_frame`, `transient_callback`, `in_flight_http:N`)
  so the agent knows whether to wait, retry, or proceed.
- New `ignore_animations: true` param drops the scheduled-frame and
  transient-callback checks; waits only for HTTP. Use on screens with
  continuous spring animations (custom sliders, looping animations)
  that never visually settle.

### route_stack — works without integrator wiring

- Multi-navigator route tracking now reads `Navigator.pages` from the
  live Element tree at snapshot time. AutoRoute / GoRouter / any
  page-based router gets full `route_stack` coverage with **zero**
  observer wiring — `createObserver()` becomes optional (still
  available as a fallback for imperative `Navigator.pushNamed` apps).
- Returns the full back-stack of each navigator, deepest-first:
  `["UserProfileRoute", "AccountRoute", "MainRoute"]` instead of just
  the leaf.

### screenshot — first-frame race fixed

- If no `RepaintBoundary` is found on the first call (cold start, no
  frame has rasterized yet), awaits one `endOfFrame` and retries
  before failing. Eliminates the spurious `"no RepaintBoundary found"`
  the agent used to hit on the first screenshot of a session.

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
