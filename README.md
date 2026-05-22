# agent-wires

[![flutter_qa_probe](https://img.shields.io/pub/v/flutter_qa_probe.svg?label=flutter_qa_probe)](https://pub.dev/packages/flutter_qa_probe)
[![flutter_qa_mcp](https://img.shields.io/pub/v/flutter_qa_mcp.svg?label=flutter_qa_mcp)](https://pub.dev/packages/flutter_qa_mcp)
[![CI](https://github.com/mohn93/agent-wires/actions/workflows/ci.yml/badge.svg)](https://github.com/mohn93/agent-wires/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> A runtime probe + MCP server that lets an LLM agent **perceive** and
> **drive** a real Flutter app, without `Semantics` annotations or
> screenshot-based vision.

The agent sees a denoised semantic tree (16 elements per screen, not 800)
and can tap, type, scroll, wait for navigation, read logs, and watch
network calls — through 18 MCP tools. The probe lives inside your app as
a dev dependency, the server runs locally, your data never leaves the
machine.

## Two packages

| Package | Lives where | Purpose |
|---|---|---|
| [`flutter_qa_probe`](packages/flutter_qa_probe) | inside your Flutter app (dev dep) | Reads the live widget tree, synthesises gestures, captures logs + HTTP. Registers `ext.qa.*` service extensions. No-op in release. |
| [`flutter_qa_mcp`](packages/flutter_qa_mcp)   | global CLI on your dev machine    | Boots the app, attaches to its VM service, exposes everything as MCP tools the agent can call. Also serves a local human-curation dashboard. |

## Quick start (under 10 minutes)

### 1. Add the probe to your Flutter app

```yaml
# pubspec.yaml
dev_dependencies:
  flutter_qa_probe: ^0.1.0
```

```dart
// lib/main.dart
import 'package:flutter_qa_probe/flutter_qa_probe.dart';

void main() {
  FlutterQAProbe.install();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [
        FlutterQAProbe.routeTracker.createObserver(),
      ],
      home: const HomePage(),
    );
  }
}
```

### 2. Install the MCP server

```bash
dart pub global activate flutter_qa_mcp
```

### 3. Point your MCP client at it

```jsonc
// ~/.claude.json  (Claude Code)
{
  "mcpServers": {
    "flutter-qa": {
      "command": "flutter_qa_mcp",
      "args": [
        "run",
        "--project", "/path/to/your/flutter/app",
        "-d",        "<device-id from `flutter devices`>"
      ]
    }
  }
}
```

Restart your client and ask the agent to take a snapshot.

→ Full walkthrough: [docs/getting-started.md](docs/getting-started.md).

## What the agent sees

On a real production sign-in screen, the agent's view before vs. after
the probe's denoise pass:

| | |
|---|---|
| **Raw widget tree** | ~800 nodes |
| **Promoted (interactive)** | ~99 |
| **After dedup + label inference** | **16** elements, each uniquely labelled |

A typical labelled element:

```json
{
  "id": "e_12",
  "role": "list_item",
  "label": "mohanned.ly · 2026-06-24 · Active",
  "bounds": { "x": 64, "y": 683, "w": 358, "h": 64 }
}
```

## A typical agent loop

```
snapshot                       → see what's on the screen
tap("Sign in")                 → drive the UI
wait_for_route("HomeRoute")    → block until navigation settles
get_network since=<cursor>     → ✓ POST /auth  HTTP 200 in 850ms
get_logs    since=<cursor>     → ResourceBus emitted AuthState.authenticated
snapshot                       → confirm the new state
```

The whole tool surface, with input schemas, is documented in the
[`flutter_qa_mcp` README](packages/flutter_qa_mcp#tool-surface-18-tools).

## How it works

```
┌─────────────────────────────────────────────────────┐
│  LLM agent (any MCP client)                         │
└────────────────────────┬────────────────────────────┘
                         │ MCP (JSON-RPC over stdio)
                         ▼
┌─────────────────────────────────────────────────────┐
│  flutter_qa_mcp  (Dart CLI, separate process)       │
│    18 tools                                         │
│    AST source-location proposals                    │
│    per-project semantic map (.flutter_qa/map.json)  │
│    human-curation dashboard (localhost:7345)        │
└────────────────────────┬────────────────────────────┘
                         │ Dart VM Service (WebSocket)
                         ▼
┌─────────────────────────────────────────────────────┐
│  Your Flutter app (debug / profile mode)            │
│    flutter_qa_probe  (in-process)                   │
│      ext.qa.snapshot, .tap, .wait_for_route, …      │
│      walks live Element tree                        │
│      synthesises gestures via GestureBinding        │
│      captures debugPrint + HTTP                     │
└─────────────────────────────────────────────────────┘
```

The single Flutter feature that makes this all work is
`dart:developer.registerExtension`: it lets in-process Dart code expose
named functions on the VM service URL, so an external tool can call them
over WebSocket and the response is computed with full access to the
running app's state.

## Repo layout

```
packages/
├── flutter_qa_probe/      runs INSIDE your app  — VM service extensions
└── flutter_qa_mcp/        runs OUTSIDE the app  — MCP server CLI

examples/
└── demo_app/              tiny Flutter app for the e2e suite

docs/
├── getting-started.md     10-minute walkthrough
└── superpowers/
    ├── specs/             original design docs
    └── plans/             per-plan task breakdowns
```

## Tests

```bash
# Unit tests (fast, no device needed)
( cd packages/flutter_qa_probe && flutter test )    # ~75 tests
( cd packages/flutter_qa_mcp   && dart test    )    # ~46 tests, 3 e2e skipped

# End-to-end (requires a connected device / simulator)
cd packages/flutter_qa_mcp
FLUTTER_QA_E2E_DEVICE=<device-id> dart test --run-skipped --tags e2e
```

Three e2e tests run against `examples/demo_app`:

- `snapshot_e2e_test.dart` — boot, snapshot, find "Go to cart"
- `drive_e2e_test.dart` — snapshot → tap → wait_for_route → snapshot
- `augmentation_e2e_test.dart` — `label_element` promotes unresolved → resolved

Each takes ~90 s end-to-end (mostly the Xcode build).

## Status & roadmap

`0.1.0` — first published release. Verified end-to-end on a real
production app (auth + multi-tab navigation + DNS settings + invoice
list, ~9 screens). Tool surface and JSON shapes are stable from this
release.

Stretch items the original design defers:

- **`print()` capture** — apps using bare `print` (not `debugPrint`) need
  to wrap `runApp` in a custom zone. A `FlutterQAProbe.installAndRunApp`
  helper would do this automatically.
- **WebView introspection** — `WKWebView` / Android WebView content is
  invisible to the probe. Companion JS bridge needed.
- **State-management adapters** — Riverpod / Bloc / Provider introspection
  to enable `read_state` + assertions.
- **Network request/response bodies** — we capture method / url / status /
  duration; bodies (with size cap + header redaction) would enable
  "why did this 401" debugging.
- **iOS native dialogs** — system permission prompts (notifications,
  camera) aren't in the Flutter widget tree. Workaround:
  `xcrun simctl push` to pre-grant on the simulator.

See [`docs/superpowers/specs/`](docs/superpowers/specs/) for the full
design and the brainstorming history.

## Contributing

Issues and PRs welcome. The codebase is ~3500 lines of Dart split across
two clean packages; the [`flutter_qa_probe` README](packages/flutter_qa_probe#how-the-snapshot-stays-small)
explains the snapshot pipeline in three paragraphs.

## License

[MIT](LICENSE) — Copyright (c) 2026 Mohanned Benmesken
