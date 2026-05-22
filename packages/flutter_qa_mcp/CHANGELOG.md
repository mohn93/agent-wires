# Changelog

## 0.1.0

Initial public release.

- 18 MCP tools across five categories: perception (`snapshot`, `inspect`,
  `screenshot`), action (`tap`, `long_press`, `swipe`, `enter_text`,
  `clear_text`, `scroll`, `press_back`), sync (`wait_for_idle`,
  `wait_for_route`, `wait_for_element`), observability (`get_logs`,
  `get_network`), and memory (`label_element`, `get_labels`, `recall`).
- `flutter_qa_mcp run` — boots `flutter run --machine`, auto-discovers
  the VM service URI, and serves MCP over stdio in one process.
  Forwards `--flavor`, `-t/--target`, `--dart-define`.
- `flutter_qa_mcp serve --attach <ws-uri>` — attaches to an already-
  running app.
- `flutter_qa_mcp review` — local human-curation dashboard at
  `localhost:7345` for labelling unresolved widgets. Per-project
  persistence in `.flutter_qa/map.json`.
- Snapshot enrichment — merges human labels and source-location
  proposals (via the analyzer package) before returning to the agent.
- Set-of-Mark mode — `screenshot(annotated: true)` overlays numbered
  boxes for vision-augmented agents.
- Requires the target app to have
  [`flutter_qa_probe`](https://pub.dev/packages/flutter_qa_probe)
  installed.
