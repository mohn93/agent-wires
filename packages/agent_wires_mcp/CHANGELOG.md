# Changelog

## 0.1.4

Docs-only release. No code changes — refreshes the README to match the 0.1.3
tool surface and behaviour so the pub.dev page is accurate.

- Removes the `-d` device pin from the MCP config examples (it contradicted
  the "don't pin at registration" guidance and is the phone-vs-simulator stall
  trap); the agent picks a device at session time via `list_devices` +
  `boot_app`.
- Corrects the tool count to 24.
- Documents that `screenshot` returns `{path, …}` by default (base64 via
  `return_base64: true`).
- `recommendedProbeVersion` tracks `agent_wires_probe` 0.1.6.

## 0.1.3

Connection- and lifecycle-hardening from a real LLM-agent driving session
(physical iPhone, then simulator) where a dropped VM-service connection
cascaded into multi-minute hangs and leaked processes. No tool additions;
`app_status` gains `probe_version` / `probe_version_warning` / `paused_at_start`
fields, and `hot_reload` / `hot_restart` failures gain `recoverable` + `hint`.

### Fail-fast instead of hanging on a dead connection

- **Per-call timeout + connection-lost latch.** When the device VM-service
  connection dropped (`Service connection disposed`, JSON-RPC `-32603`), every
  `ext.qa.*` call used to block on the dead socket until cancelled — `boot_app`
  ran 601s, `get_logs` 633s, even `stop_app` 219s. `VmClient` now bounds each
  call and latches a lost-connection state the instant the socket closes, a
  call returns `disposed`, or a call times out; subsequent calls and
  `isProbeAlive` fail immediately with a clear "reattach or reboot" error. A
  dead connection is distinguished from a stale isolate, so it no longer
  triggers a rebind that would re-hang.
- **Teardown never blocks on the VM-service.** `stop_app` bounds VM-service
  disposal so it always tears down the OS process, even when the connection is
  already dead.

### Reap the whole flutter process tree

- **No more orphaned `flutter run` / DDS / devicectl / iproxy.** `stop_app`
  (and server exit on SIGINT/SIGTERM) now snapshots the descendant process
  tree before killing flutter — children reparent to launchd the moment
  flutter dies — then SIGTERM→SIGKILL the lot. Stops the per-cycle leak that
  left multiple servers/runs contending for the same device and VM-service.

### Resume a paused-at-start launch

- **Frozen `--start-stopped` apps now run.** A physical iPhone launched via
  `devicectl … --start-stopped` boots with `main()` paused; nothing resumed it,
  so the app sat frozen while `app_status` read `ready`. Attach now resumes any
  paused-at-start isolate **before** locating the QA isolate (a paused isolate
  hasn't registered the probe yet). When a resume can't be confirmed,
  `app_status` reports `paused_at_start: true` instead of a misleading
  healthy status.

### Hot reload/restart — recover from DevFS wedges

- **Retry-then-explain on `DevFS synchronization failed`.** `hot_reload` /
  `hot_restart` retry once (the failure is often transient); if it still
  fails, the result carries `recoverable: false` and a `hint` to run
  `stop_app` + `boot_app`, instead of a bare `success: false`.

### Smaller robustness wins

- **`boot_app(device_id)` switches devices without a deadlock.** A device
  switch on a running session force-stops it (process-level) instead of
  rejecting with "call stop_app first" — which used to deadlock when the
  VM-service was already dead.
- **Probe/server version-skew warning.** The probe reports its version over
  `ext.qa.ping`; `app_status` surfaces `probe_version` and warns when it
  differs from the version this server pairs with (`0.1.5`).
- **`get_logs` can't blow the client token budget.** Oversized
  `message` / `error` / `stack` fields are truncated (default 4000 chars each,
  with a dropped-char marker) so a single ~110k-char Flutter stack no longer
  overruns the MCP client limit. Pagination is preserved.

## 0.1.2

Hot-restart robustness from real LLM-agent driving sessions. No tool
additions; `app_status` gains a `probe_attached` field.

### Self-healing isolate binding

- **Recovers from hot restart automatically.** A hot restart collects
  the QA isolate and starts a new one. The client used to keep calling
  the dead isolate id, so every `ext.qa.*` call failed with
  `[Sentinel kind: Collected]` for the rest of the session and never
  recovered. `callExtension` now re-resolves the live `ext.qa.*` isolate
  and retries once on a stale-isolate error, so a single tool call
  recovers transparently.
- **`app_status` reports `probe_attached`.** Distinct from `state`,
  which only tracks the `flutter run` process: after a hot restart the
  process stays up (`state` stays `ready`) but the probe moves to a
  fresh isolate. `state:"ready"` with `probe_attached:false` now tells
  the agent the probe is reattaching, instead of looking healthy while
  every call fails. The check re-resolves and rebinds when the bound
  isolate has been collected.
- **Clearer error when the probe is truly gone.** If re-resolution
  fails (the app exited, or hot-restarted without
  `AgentWiresProbe.install()`), the agent gets an actionable message
  instead of the raw VM-service sentinel string.

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
