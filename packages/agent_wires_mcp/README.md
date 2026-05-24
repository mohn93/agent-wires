# agent_wires_mcp

[![pub package](https://img.shields.io/pub/v/agent_wires_mcp.svg)](https://pub.dev/packages/agent_wires_mcp)

MCP server that bridges an LLM agent to a running Flutter app via the Dart
VM service. Pairs with
[`agent_wires_probe`](https://pub.dev/packages/agent_wires_probe) — together
they let an LLM agent perceive and drive your app for end-to-end testing.

The agent sees a denoised semantic tree (16 elements, not 800) and can
tap, type, scroll, wait, take screenshots, read logs, and watch network
calls. State that needs human curation (labels for unlabeled controls)
persists in your project as `.flutter_qa/map.json`.

> See [agent-wires/README.md](https://github.com/mohn93/agent-wires#readme)
> for the full architecture and a 10-minute walkthrough.

## Install

```bash
dart pub global activate agent_wires_mcp
```

This installs the `agent_wires_mcp` executable globally. Confirm with:

```bash
agent_wires_mcp --version
```

If `agent_wires_mcp` isn't on your `PATH`, follow the
[Dart docs](https://dart.dev/tools/pub/cmd/pub-global#running-a-script-from-your-path).

## Use

Configure your MCP client to spawn `agent_wires_mcp run` against your app.

**Claude Code** — `~/.claude.json`:

```jsonc
{
  "mcpServers": {
    "flutter-qa": {
      "command": "agent_wires_mcp",
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
already-running app, use `agent_wires_mcp serve --attach <ws-uri>` instead.

## Subcommands

```
agent_wires_mcp run     boot a Flutter app and serve MCP in one step
agent_wires_mcp serve   attach to an already-running VM service URI
agent_wires_mcp review  open the human-curation dashboard
```

### `run` flags

| Flag | Purpose |
|---|---|
| `--project <dir>` | the Flutter app directory (default: cwd) |
| `-d, --device <id>` | target device (from `flutter devices`) |
| `--flavor <name>` | passed through as `flutter run --flavor` |
| `-t, --target <path>` | entry-point Dart file |
| `--dart-define KEY=VALUE` | repeatable, forwarded to `flutter run` |

## Tool surface (23 tools)

| Category | Tools |
|---|---|
| Lifecycle | `list_devices`, `boot_app`, `app_status`, `stop_app`, `hot_reload`, `hot_restart` |
| Perception | `snapshot`, `inspect`, `screenshot` (optional Set-of-Mark overlay) |
| Action | `tap`, `long_press`, `swipe`, `enter_text`, `clear_text`, `scroll`, `press_back` |
| Sync | `wait_for_idle` (+ `ignore_animations` flag), `wait_for_route`, `wait_for_element` |
| Observability | `get_logs`, `get_network` |
| Memory | `label_element`, `get_labels`, `recall` |

A typical agent loop:

```
list_devices                → discover what flutter can target
boot_app(device_id="...")   → compile + launch on the chosen device
snapshot                    → see what's on the screen
tap("Sign in")              → drive the UI
wait_for_route("HomeRoute") → block until the navigation completes
get_network since=<cursor>  → see what HTTP that triggered
get_logs    since=<cursor>  → see what the app printed
snapshot                    → confirm the new state
```

When the user edits source code:

```
hot_reload                  → re-inject sources, preserve state + route
snapshot                    → confirm the change landed
```

### Why this server uses a "stateful lifecycle" instead of pinning at registration

The MCP registration command does not need `-d` for a device. Instead, the
agent calls `list_devices` and asks the user which to target — pinning a
specific simulator (or worse, accidentally a physical phone with stalled
codesigning) at registration time turns first-launch into a 10-minute
black box. `boot_app` accepts the chosen device id; selection sticks
until `stop_app`.

For long boots, pass `wait: false` to `boot_app` — it returns
`{state: "booting"}` immediately and the agent polls `app_status` to
watch `latest_progress` ("Running Xcode build...", "Installing Pods...")
and decide whether to keep waiting or `stop_app`. Subsequent perception
and action tools auto-wait for the boot to finish.

## Human-in-the-loop dashboard

When the agent encounters a tappable widget without a recognisable label
(a bare `GestureDetector`, a custom-painted control), it lands in the
snapshot's `unresolved[]` array. The MCP server proposes labels from
source-location analysis, but a human confirms via the review dashboard:

```bash
agent_wires_mcp review --project-root /path/to/your/app
# → open http://localhost:7345
```

Accepted labels persist in `.flutter_qa/map.json`. Commit that file with
your code so the rest of your team gets the same vocabulary.

## Requires

- **Dart SDK 3.5+** (ships with Flutter)
- **Flutter SDK 3.24+** — `agent_wires_mcp run` shells out to `flutter run`
- The target app has [`agent_wires_probe`](https://pub.dev/packages/agent_wires_probe)
  installed and `AgentWiresProbe.install()` called from `main()`

## License

[MIT](https://github.com/mohn93/agent-wires/blob/main/LICENSE)
