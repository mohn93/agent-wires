# Changelog

## 0.1.1

Post-0.1.0 iteration driven by real LLM-agent driving sessions. **Tool
count grows from 18 → 23** (5 new lifecycle tools). Several tool input
schemas gain optional flags; nothing existing breaks.

### New: lifecycle tools

- `list_devices` — runs `flutter devices --machine` and returns a
  curated `[{id, name, platform, is_emulator, is_supported, sdk}, ...]`
  list. Agent calls this when multiple devices might be connected
  (the classic 10-min-hang trigger: phone + sim, flutter picks the
  phone and stalls on signing).
- `boot_app` / `app_status` / `stop_app` — explicit lifecycle instead
  of "boot happens magically on first tool call." `boot_app` accepts
  `device_id` (pick the device per session), `wait` (false for
  fire-and-forget so the agent can poll progress). Sticks the device
  choice until the next `stop_app`.
- `hot_reload` — re-injects edited Dart sources, preserves state +
  current route. Lazy mode uses `flutter run --machine`'s `app.restart`
  (true Flutter reload with reassemble); attached mode falls back to
  VM-service `reloadSources` (sources swap, no reassemble).
- `hot_restart` — tears down the isolate and re-runs `main()`. State
  lost. Only supported in lazy mode (where we own the flutter
  subprocess). Attached mode returns a clear "use your own restart"
  error.

### Boot: visible instead of black box

- **Lazy boot.** `agent_wires_mcp run` no longer blocks on
  `flutter run --machine` before opening MCP stdio. The handshake
  returns in milliseconds; flutter only starts when the agent calls
  `boot_app` (or any other tool, via auto-boot). Previously Claude
  Code's 30s connection timeout killed every cold-cache session.
- **Progress streaming.** Each `app.progress` and non-error
  `daemon.logMessage` event from flutter is captured on the session,
  surfaced in `app_status.latest_progress`, and written to MCP-server
  stderr so Claude Code's MCP log viewer also shows it. A long Xcode
  build / pod install now reads as "Running Xcode build..." in
  app_status instead of a silent 5-minute wait.
- **Fail-fast on launch errors.** `app.stop` with an error payload,
  or any error-level daemon log, immediately fails the boot future
  with that message. No more 10-minute timeouts on "No supported
  devices connected."
- **Recovery.** Lazy sessions in `exited` reset to `idle` on the next
  `ensureReady`; the agent can retry `boot_app` after a timeout or
  `stop_app` without reconstructing the MCP server. Attached sessions
  stay terminal (we don't own that flutter process).
- Default boot timeout 5 min → 10 min — large apps with firebase /
  syncfusion / flutter_quill routinely run past 5 on a cold compile.

### Perception tools — smaller, more accurate

- `snapshot` gains `include_unresolved: false` by default. The
  unresolved array (the worst noise: 10–25k chars of unlabelled
  Listeners, decorative Switches, FAB carriers) is hidden; the
  count is reported as `unresolved_count` instead. Agents that need
  to drive a hidden widget (pin-code fields) opt in explicitly.
- `screenshot` writes the PNG to a tmp file and returns
  `{path, width, height, size_bytes}` by default — was 329k chars of
  inline base64 that the agent couldn't actually read. The old
  behavior is available via `return_base64: true`.
- `inspect` gains `include_descendants` (default true) and
  `descendant_depth` (default 3) — returns a subtree view with
  `painter` + `size` exposed for `CustomPaint` descendants. Lets the
  agent answer "what's inside this Card?" or "is this region drawn
  pixels?" in one call.

### Sync — diagnose what's keeping the app awake

- `wait_for_idle` returns a structured payload on timeout:
  `{idle, blocked_by, in_flight_http, has_scheduled_frame,
  in_transient_callback}`. The agent now knows whether to wait
  longer, retry, or proceed.
- New `ignore_animations` flag — drops the frame/animation checks,
  waits only for HTTP. Use on screens with continuous spring
  animations that never visually settle.

### Tool descriptions

- All 23 tool descriptions rewritten to disambiguate (snapshot vs.
  screenshot, the three `wait_for_*` siblings) and teach the canonical
  agent loop. The biggest behavioral change: agents now reach for
  `snapshot` first by default; `screenshot` correctly signals
  "almost always prefer snapshot."

### Internal

- `AppSession` introduced as the lifecycle hub; runner + VM client
  state lives there with explicit state machine (`idle`, `booting`,
  `ready`, `exited`).
- `FlutterRunner` captures the appId from `app.started`, routes
  machine-protocol responses to per-request completers, exposes a
  general-purpose progress callback.
- `DeviceLister` wraps `flutter devices --machine`; parser tolerates
  leading log lines.

## 0.1.0

Initial public release.

- 18 MCP tools across five categories: perception (`snapshot`, `inspect`,
  `screenshot`), action (`tap`, `long_press`, `swipe`, `enter_text`,
  `clear_text`, `scroll`, `press_back`), sync (`wait_for_idle`,
  `wait_for_route`, `wait_for_element`), observability (`get_logs`,
  `get_network`), and memory (`label_element`, `get_labels`, `recall`).
- `agent_wires_mcp run` — boots `flutter run --machine`, auto-discovers
  the VM service URI, and serves MCP over stdio in one process.
  Forwards `--flavor`, `-t/--target`, `--dart-define`.
- `agent_wires_mcp serve --attach <ws-uri>` — attaches to an already-
  running app.
- `agent_wires_mcp review` — local human-curation dashboard at
  `localhost:7345` for labelling unresolved widgets. Per-project
  persistence in `.flutter_qa/map.json`.
- Snapshot enrichment — merges human labels and source-location
  proposals (via the analyzer package) before returning to the agent.
- Set-of-Mark mode — `screenshot(annotated: true)` overlays numbered
  boxes for vision-augmented agents.
- Requires the target app to have
  [`agent_wires_probe`](https://pub.dev/packages/agent_wires_probe)
  installed.
