# agent_wires_probe

[![pub package](https://img.shields.io/pub/v/agent_wires_probe.svg)](https://pub.dev/packages/agent_wires_probe)

Runtime probe that exposes a Flutter app's widget tree to QA agents over the
Dart VM service. Pairs with
[`agent_wires_mcp`](https://pub.dev/packages/agent_wires_mcp) — together they
let an LLM agent perceive and drive your app for end-to-end testing without
relying on `Semantics` annotations or screen-scraping.

The probe lives **inside** your app (as a dev dependency) and registers a
small set of `ext.qa.*` service extensions that read the live Element tree,
synthesise gestures, and capture logs / network. The MCP server connects
from outside and exposes those as tools an agent can call.

> See [agent-wires/README.md](https://github.com/mohn93/agent-wires#readme)
> for the full architecture and a 10-minute walkthrough.

## Install

```yaml
# pubspec.yaml of the Flutter app you want to drive
dev_dependencies:
  agent_wires_probe: ^0.1.0
```

```bash
flutter pub get
```

## Use

```dart
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/agent_wires_probe.dart';

void main() {
  AgentWiresProbe.install();          // ① register ext.qa.* on the VM service
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [
        AgentWiresProbe.routeTracker.createObserver(),   // ② track active route
      ],
      home: const HomePage(),
    );
  }
}
```

`install()` is a no-op in release builds (`kReleaseMode`); the probe never
ships to your users. The route observer factory must be called **per
navigator** — apps with nested navigators (AutoRoute tab UIs, drawers)
should pass `createObserver()` into every `navigatorObservers` factory.

Requires `--track-widget-creation` (default in debug + profile mode under
`flutter run`).

## What the probe exposes

The MCP server calls these by name; you only need to know they exist if
you're building a different client. Full request/response shapes are in
`lib/src/extensions/`.

| Service extension | Purpose |
|---|---|
| `ext.qa.ping` | health check, returns probe version |
| `ext.qa.snapshot` | denoised semantic tree (16 elements vs. raw 800+); per-element `state` for Switch/Checkbox/Radio/Slider; drops widgets buried under pushed routes |
| `ext.qa.inspect` | widget chain, properties, descendant subtree; `painter` + `size` for `CustomPaint` descendants |
| `ext.qa.screenshot` | base64 PNG of the current frame (auto-waits one frame if nothing has rasterized yet) |
| `ext.qa.tap` / `long_press` / `swipe` | gesture synthesis through Flutter's `GestureBinding` |
| `ext.qa.enter_text` / `clear_text` | drives the focused `EditableTextState` directly |
| `ext.qa.scroll` | jumps the nearest `ScrollPosition` |
| `ext.qa.press_back` | pops the current route |
| `ext.qa.wait_for_idle` | true when scheduler + timers + HTTP all settle; `ignore_animations` skips the frame check; returns `blocked_by` on timeout |
| `ext.qa.wait_for_route` | resolves when a named route becomes current |
| `ext.qa.wait_for_element` | resolves when a label/role match appears |
| `ext.qa.get_logs` | drains a 500-entry ring buffer of `debugPrint` / `FlutterError` / uncaught zone errors |
| `ext.qa.get_network` | every HTTP exchange: method / url / status / duration |

## How the snapshot stays small

A raw widget tree on a Flutter screen is ~800 nodes — useless for an LLM.
The probe runs three passes:

1. **Classify** — promote interactive widgets (`Button`, `TextField`,
   `Listener`-with-handlers, etc.), skip layout (`Padding`, `Column`),
   collapse leaves (`Text` becomes its parent's label).
2. **Dedup** — drop the `InkWell → GestureDetector → Listener` chain
   inside a button (they share the button's rect); drop Scaffold-sized
   wrappers that contain real targets.
3. **Label** — concatenate up to four descendant `Text` widgets so a card
   reads `"Sub Total · 9,709.50 LYD · Unpaid · 342844"` rather than just
   `"Sub Total"`.

Output of a real production sign-in screen: 99 → 16 elements, each one a
single tappable target the agent can name.

## Making custom-painted widgets agent-friendly

Anything drawn inside a `CustomPaint` / `Canvas` (custom sliders, charts,
gauges, signature pads) has **no widget tree** for the probe to walk —
the thumb of a 20px circle painted into a `Canvas` is just pixels. An
agent calling `inspect` on the parent will see `painter:
PrecisionReactiveSliderPainter, size: 320.0x60.0` and know the region
is unaddressable, but it can't synthesise a meaningful tap on the
specific sub-region.

Two integrator-side fixes make these widgets driveable:

```dart
// 1. Wrap the interactive piece in Semantics with a button: true label.
//    The probe surfaces it as a named tappable element.
Semantics(
  button: true,
  label: 'slider thumb',
  child: CustomPaint(painter: thumbPainter, size: const Size(20, 20)),
)

// 2. Or attach a Key — the agent can target it via the element's
//    `key_value` field in the snapshot.
CustomPaint(
  key: const ValueKey('slider-thumb'),
  painter: thumbPainter,
  size: const Size(20, 20),
)
```

If neither is possible, the agent will fall back to coordinate-based
`swipe` or `tap` using the parent's `bounds` — workable but pixel-fragile.

## License

[MIT](https://github.com/mohn93/agent-wires/blob/main/LICENSE)
