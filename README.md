# ai_mobile_eyes — Flutter QA MCP

A runtime probe + MCP server that lets LLM agents perceive and drive Flutter
apps for QA. The agent can take semantic snapshots of the current screen,
tap and scroll and type, wait for navigation to settle, and learn an app's
vocabulary over time through human curation.

**Status:** feature-complete per the original design. Verified end-to-end
against an iOS simulator. Distribution (pub.dev / Homebrew) and the polish
items in the [punch list](#punch-list) are the work that remains.

## Quick start

```bash
# In your Flutter app's pubspec.yaml:
dev_dependencies:
  flutter_qa_probe:
    path: /path/to/ai_mobile_eyes/packages/flutter_qa_probe

# In your lib/main.dart:
import 'package:flutter_qa_probe/flutter_qa_probe.dart';
void main() {
  FlutterQAProbe.install();
  runApp(MyApp());
}
```

Then point your MCP client (Claude Code, Claude Desktop, Cursor, …) at:

```json
{
  "mcpServers": {
    "flutter-qa": {
      "command": "dart",
      "args": [
        "run", "/path/to/ai_mobile_eyes/packages/flutter_qa_mcp/bin/flutter_qa_mcp.dart",
        "run", "--project", "/path/to/your/flutter/app", "-d", "<device id>"
      ]
    }
  }
}
```

→ full walkthrough in [docs/getting-started.md](docs/getting-started.md).

## What the agent gets

**16 MCP tools** across four categories:

| Category | Tools |
|---|---|
| Perception | `snapshot`, `inspect`, `screenshot` (with optional Set-of-Mark overlay) |
| Action | `tap`, `long_press`, `swipe`, `enter_text`, `clear_text`, `scroll`, `press_back` |
| Sync | `wait_for_idle`, `wait_for_route`, `wait_for_element` |
| Memory | `label_element`, `get_labels`, `recall` |

Plus a `flutter_qa_mcp review` CLI subcommand that opens a localhost
dashboard for curating unresolved labels.

## How it works

```
┌─────────────────────────────────────────────────────┐
│  LLM Agent (any MCP client)                         │
└────────────────────────┬────────────────────────────┘
                         │ MCP / stdio
                         ▼
┌─────────────────────────────────────────────────────┐
│  flutter_qa_mcp (Dart CLI, this repo)               │
│   - 16 tools + dashboard                            │
│   - persistent semantic map @ .flutter_qa/map.json  │
└────────────────────────┬────────────────────────────┘
                         │ Dart VM Service
                         ▼
┌─────────────────────────────────────────────────────┐
│  Your Flutter app (debug or profile mode)           │
│   flutter_qa_probe (dev dependency)                 │
│    - VM service extensions: ext.qa.snapshot,       │
│      ext.qa.tap, ext.qa.wait_for_route, …          │
└─────────────────────────────────────────────────────┘
```

The probe walks the live Widget tree, classifies and denoises it (a typical
800-node tree collapses to ≈15–30 elements an LLM can reason about), and
exposes the result via VM service extensions. The MCP server enriches the
raw output with source-location label proposals (`AstParser` resolves
`creation_location` to the enclosing function name) and any human labels
from the per-project semantic map.

## Layout

```
packages/
├── flutter_qa_probe/      Dart Flutter package, dev dep in app under test
└── flutter_qa_mcp/        Standalone MCP server (CLI + library)

examples/
└── demo_app/              Tiny Flutter app for the e2e suite

docs/
├── getting-started.md     10-minute walkthrough
└── superpowers/
    ├── specs/             Design specs
    └── plans/             Per-plan task breakdowns
```

## Running the tests

Unit tests (fast, no device needed):

```bash
cd packages/flutter_qa_probe && flutter test    # 57 tests
cd packages/flutter_qa_mcp   && dart test       # 46 tests, 3 e2e skipped
```

End-to-end tests (require a connected device or simulator):

```bash
cd packages/flutter_qa_mcp
FLUTTER_QA_E2E_DEVICE=<device id> \
  dart test --run-skipped --tags e2e
```

Three tests are wired:

- `snapshot_e2e_test.dart` — boot app, snapshot, find "Go to cart"
- `drive_e2e_test.dart` — snapshot → tap → wait_for_route → snapshot
- `augmentation_e2e_test.dart` — label_element promotes unresolved → resolved

Each takes ~90 s end-to-end (mostly Xcode build).

## Punch list

Things that work but should improve before broader use:

- **Distribution.** Probe and MCP server are path-deps. Publish to pub.dev,
  ship a compiled binary, add a Homebrew formula.
- **WebView introspection.** Native probe can't see inside `WKWebView` /
  Android WebView. Needs a companion JS bridge.
- **State-management adapters.** Riverpod / Bloc / Provider introspection
  for `read_state` + assertions.
- **`getDetailsSubtree` performance.** Per-element inspector calls add up on
  large trees. A batched fetch would cut snapshot latency significantly.
- **Network and state_diff proposals.** Spec defers these; would meaningfully
  improve the proposal quality.
- **Dashboard polish.** Per-element screenshot crop, conflict resolution UI,
  SSE/WebSocket for instant updates instead of 3 s polling.

See [docs/superpowers/specs/](docs/superpowers/specs/) for the full design.
