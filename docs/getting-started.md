# Getting Started — flutter_probe + flutter_probe_mcp

Drive a Flutter app with an LLM agent in ~10 minutes. You'll wire a probe into a
Flutter app, configure your MCP client (Claude Code, Claude Desktop, or Cursor)
to spawn the bundled `flutter_probe_mcp run` command, and then ask the agent to
take a snapshot.

## Prerequisites

- Flutter SDK 3.24+ and a Flutter app you can run locally
- Dart SDK 3.5+ (ships with Flutter)
- A connected device or simulator: `flutter devices` should list at least one
  non-desktop entry
- An MCP client. This guide covers Claude Desktop and Claude Code; the same
  pattern works for Cursor and any other stdio-MCP client.

## Step 1 — Add the probe to your Flutter app (≈2 minutes)

In your app's `pubspec.yaml`, add the probe as a **dev dependency** (it
short-circuits to a no-op in release builds, but keeping it out of the
release dep graph is cleaner):

```yaml
dev_dependencies:
  flutter_probe: ^0.1.0
```

```bash
flutter pub get
```

In `lib/main.dart`, install the probe before `runApp` and wire the route
tracker into your `MaterialApp`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_probe/flutter_probe.dart';

void main() {
  FlutterProbe.install();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [FlutterProbe.routeTracker.createObserver()],
      home: const MyHomePage(),
    );
  }
}
```

That's the entire integration. `install()` is a no-op in `kReleaseMode` and
when called twice.

## Step 2 — Install the MCP server

```bash
dart pub global activate flutter_probe_mcp
```

This puts a `flutter_probe_mcp` executable on your `PATH`. Confirm:

```bash
flutter_probe_mcp --version
```

If `flutter_probe_mcp` isn't found, follow the
[Dart docs on running global scripts](https://dart.dev/tools/pub/cmd/pub-global#running-a-script-from-your-path).

## Step 3 — Configure your MCP client

The `run` subcommand does everything in one process: boots
`flutter run --machine`, captures the VM service URI, attaches to the QA
isolate, and serves MCP over stdio.

### Claude Code

Add to `~/.claude.json` (create the file if it doesn't exist):

```json
{
  "mcpServers": {
    "flutter-qa": {
      "command": "flutter_probe_mcp",
      "args": [
        "run",
        "--project",
        "/Users/you/your-flutter-app",
        "-d",
        "<your device id from `flutter devices`>"
      ]
    }
  }
}
```

Restart Claude Code. The agent now has access to all 18 tools.

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS)
or the equivalent path for your OS:

```json
{
  "mcpServers": {
    "flutter-qa": {
      "command": "flutter_probe_mcp",
      "args": [
        "run",
        "--project",
        "/Users/you/your-flutter-app",
        "-d",
        "<your device id>"
      ]
    }
  }
}
```

Quit and reopen Claude Desktop.

### Cursor / others

Same shape: spawn `flutter_probe_mcp run --project <app dir> -d <device>` over
stdio. Consult your client's MCP documentation for the config file
location.

> **Finding a device id**
>
> ```bash
> flutter devices
> ```
>
> Copy the second column (the long UUID for simulators or `00008120-…` for
> physical iOS devices). You can omit `-d` to let Flutter pick the first
> device, but explicit is more predictable.

## Step 4 — Try it (≈1 minute)

Open your MCP client and ask:

> Take a snapshot of my app and tell me what's on screen.

The agent will call `snapshot`. The first call takes ≈60 s on iOS — Xcode
needs to build and install the app the first time the MCP server spawns
`flutter run`. Subsequent calls are sub-second.

You should see the agent respond with a list of buttons, text fields, list
items, etc. from the currently visible screen.

Other things to try once the first snapshot returns:

- "Tap the Checkout button" — agent calls `snapshot` then `tap`.
- "Scroll down" — `scroll(direction: down)`.
- "Type 'hello' into the search box" — `enter_text`.
- "Take a screenshot" — `screenshot` returns base64 PNG.
- "Show me the screen with numbered boxes" — `screenshot(annotated: true)`
  draws Set-of-Mark overlays.

## Step 5 — Curate unresolved labels (≈30 seconds per element)

When the agent encounters a tappable widget with no text or icon (a bare
`GestureDetector`, custom-painted control, etc.), it lands in the snapshot's
`unresolved[]` array. The MCP server can propose labels from source-location
analysis, but a human signs off via the dashboard.

In a separate terminal:

```bash
flutter_probe_mcp review --project-root /Users/you/your-flutter-app
```

Open <http://localhost:7345>. You'll see two columns:

- **Unresolved** — entries with proposals from source-location and VLM
  analysis. Hit Accept, edit the label, or Dismiss.
- **Labeled** — entries you've confirmed. The next snapshot will use these
  labels automatically.

The dashboard polls every 3 s, so changes appear immediately on the next
agent `snapshot` call. The labels persist in `.flutter_qa/map.json` in your
project; commit that file to share the vocabulary with your team.

## Troubleshooting

- **"no isolate has ext.qa.* extensions registered"** — `FlutterProbe.install()`
  didn't run. Confirm it's the first line of `main()`, and confirm you're in
  debug or profile mode (not release).
- **First snapshot times out** — iOS first build is slow. Bump the wait by
  asking the agent to call `wait_for_idle(timeout_ms: 30000)` first.
- **`flutter` not on PATH** — `flutter_probe_mcp run` shells out to `flutter`.
  Make sure the MCP client's spawned env can find it (often means setting
  `PATH` in your shell's login profile, not just `.bashrc`).
- **VM service connects but tools return empty** — usually means the app
  hasn't pumped its first frame yet. `wait_for_idle` once, then snapshot.
- **Multiple devices** — always pass `-d <device id>`. Flutter's default
  picker can grab a desktop device, which the probe doesn't support yet.

## What's next

- The agent's full tool surface: see [README.md](../README.md).
- The design and architecture: [design spec](superpowers/specs/2026-05-21-flutter-qa-mcp-design.md).
- Per-plan task breakdowns: [docs/superpowers/plans/](superpowers/plans/).
