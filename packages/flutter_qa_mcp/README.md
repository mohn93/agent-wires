# flutter_qa_mcp

[![pub package](https://img.shields.io/pub/v/flutter_qa_mcp.svg)](https://pub.dev/packages/flutter_qa_mcp)

MCP server that bridges an LLM agent to a running Flutter app via the Dart
VM service. Pairs with
[`flutter_qa_probe`](https://pub.dev/packages/flutter_qa_probe) — together
they let an LLM agent perceive and drive your app for end-to-end testing.

The agent sees a denoised semantic tree (16 elements, not 800) and can
tap, type, scroll, wait, take screenshots, read logs, and watch network
calls. State that needs human curation (labels for unlabeled controls)
persists in your project as `.flutter_qa/map.json`.

> See [agent-wires/README.md](https://github.com/mohn93/agent-wires#readme)
> for the full architecture and a 10-minute walkthrough.

## Install

```bash
dart pub global activate flutter_qa_mcp
```

This installs the `flutter_qa_mcp` executable globally. Confirm with:

```bash
flutter_qa_mcp --version
```

If `flutter_qa_mcp` isn't on your `PATH`, follow the
[Dart docs](https://dart.dev/tools/pub/cmd/pub-global#running-a-script-from-your-path).

## Use

Configure your MCP client to spawn `flutter_qa_mcp run` against your app.

**Claude Code** — `~/.claude.json`:

```jsonc
{
  "mcpServers": {
    "flutter-qa": {
      "command": "flutter_qa_mcp",
      "args": [
        "run",
        "--project", "/Users/you/your-flutter-app",
        "-d",        "<device-id from `flutter devices`>"
      ]
    }
  }
}
```

**Claude Desktop / Cursor / others** — same shape, point at the same
binary; consult your client's MCP config docs for the file location.

The `run` subcommand boots `flutter run --machine`, auto-discovers the VM
service URI, attaches, and serves MCP over stdio in one process. For an
already-running app, use `flutter_qa_mcp serve --attach <ws-uri>` instead.

## Subcommands

```
flutter_qa_mcp run     boot a Flutter app and serve MCP in one step
flutter_qa_mcp serve   attach to an already-running VM service URI
flutter_qa_mcp review  open the human-curation dashboard
```

### `run` flags

| Flag | Purpose |
|---|---|
| `--project <dir>` | the Flutter app directory (default: cwd) |
| `-d, --device <id>` | target device (from `flutter devices`) |
| `--flavor <name>` | passed through as `flutter run --flavor` |
| `-t, --target <path>` | entry-point Dart file |
| `--dart-define KEY=VALUE` | repeatable, forwarded to `flutter run` |

## Tool surface (18 tools)

| Category | Tools |
|---|---|
| Perception | `snapshot`, `inspect`, `screenshot` (optional Set-of-Mark overlay) |
| Action | `tap`, `long_press`, `swipe`, `enter_text`, `clear_text`, `scroll`, `press_back` |
| Sync | `wait_for_idle`, `wait_for_route`, `wait_for_element` |
| Observability | `get_logs`, `get_network` |
| Memory | `label_element`, `get_labels`, `recall` |

A typical agent loop:

```
snapshot                    → see what's on the screen
tap("Sign in")              → drive the UI
wait_for_route("HomeRoute") → block until the navigation completes
get_network since=<cursor>  → see what HTTP that triggered
get_logs    since=<cursor>  → see what the app printed
snapshot                    → confirm the new state
```

## Human-in-the-loop dashboard

When the agent encounters a tappable widget without a recognisable label
(a bare `GestureDetector`, a custom-painted control), it lands in the
snapshot's `unresolved[]` array. The MCP server proposes labels from
source-location analysis, but a human confirms via the review dashboard:

```bash
flutter_qa_mcp review --project-root /path/to/your/app
# → open http://localhost:7345
```

Accepted labels persist in `.flutter_qa/map.json`. Commit that file with
your code so the rest of your team gets the same vocabulary.

## Requires

- **Dart SDK 3.5+** (ships with Flutter)
- **Flutter SDK 3.24+** — `flutter_qa_mcp run` shells out to `flutter run`
- The target app has [`flutter_qa_probe`](https://pub.dev/packages/flutter_qa_probe)
  installed and `FlutterQAProbe.install()` called from `main()`

## License

[MIT](https://github.com/mohn93/agent-wires/blob/main/LICENSE)
