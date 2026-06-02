# Action Overlay — on-screen narration of agent activity

**Status:** approved design · **Date:** 2026-06-02

## Goal

When an LLM agent drives a Flutter app through agent-wires, a human watching the
device/simulator currently sees taps and navigation happen with no indication of
*what the agent is doing*. This feature draws a transient visual at the point of
each agent action and perception — a ripple where it tapped, a trail for a
swipe, a highlight box where it pointed, a flash when it looked — so the human
gets a live, legible narration of the agent's behaviour.

The overlay is for the **human watching live**. It must **not** appear in the
agent's own `screenshot` or `snapshot`, so the agent's perception stays exactly
what the app renders.

## Scope

Visualized activities (all four categories, confirmed):

- **Touch actions** — `tap`, `long_press`, `swipe`, `scroll`, `press_back`.
- **Text entry** — `enter_text`, `clear_text`.
- **Perception / point-at** — `inspect`, `label_element`.
- **Perception / whole-screen** — `screenshot`, `snapshot`.

Out of scope (YAGNI): native per-platform overlay windows; persisting/recording
the narration; configurable per-effect styling beyond the defaults below;
showing the overlay in release builds (the probe is already debug-only).

## Approach

The probe is injected into an app whose `runApp` it does not control, so it
paints via a **single top-level `OverlayEntry`** inserted into the app's topmost
`Overlay` (every `MaterialApp`/`CupertinoApp` has one via its `Navigator`). The
entry is wrapped in `IgnorePointer`, sits above all routes, and survives route
changes. Rejected alternatives: a manual binding-level render layer (far more
code, fragile across Flutter versions) and native overlay windows (heavy,
platform-specific).

## Components (probe side — new `lib/src/overlay/` module)

### `ActionOverlayController` (pure Dart, `ChangeNotifier`)

The model. No widget dependencies, so it is fully unit-testable.

State:
- `enabled` — default `true`. When false, all pushes are no-ops.
- `suppressedForCapture` — when true, `visibleEffects` is empty (used to hide the
  overlay for the single frame a screenshot captures).
- a capped list of active `OverlayEffect`s (oldest dropped past the cap).

API the extensions call after a successful action:
- `showTap(Offset point, {bool longPress})`
- `showDrag(Offset from, Offset to)` — swipe / scroll
- `showHighlight(Rect bounds, {String? label})` — inspect / label / text fields
- `showFlash({required OverlayFlashKind kind})` — screenshot / snapshot
- `setEnabled(bool)` — clears active effects when disabling.
- `beginCaptureSuppression()` / `endCaptureSuppression()`

`visibleEffects` returns `[]` when `suppressedForCapture` is true.

### `OverlayEffect` (sealed types)

`TapEffect`, `DragEffect`, `HighlightEffect`, `FlashEffect`. Each carries its
geometry, an optional caption, and a duration; each self-expires.

### `ActionOverlayHost` (`StatefulWidget`, ticker mixin)

Hosted in the single `OverlayEntry`, wrapped in `IgnorePointer`. Listens to the
controller; drives one `AnimationController` per active effect; removes and
disposes each on completion. Renders effects with `CustomPaint`. Tagged with a
sentinel marker widget/key so the `snapshot` walker skips its subtree.

### `ActionOverlayInstaller`

Lazily locates the topmost `Overlay` (walk from `WidgetsBinding.rootElement` to
the root `Navigator`/`Overlay`) and inserts the persistent entry on the first
effect. Retries on later effects if not found yet. If the app has no `Overlay`,
logs once and no-ops — nothing breaks, the overlay simply does not show.

## Effects (default visuals — tweakable)

| Activity | Visual | Duration |
|---|---|---|
| tap / long-press | expanding ring + fading dot at the point (long-press pulses) | ~600ms |
| swipe / scroll | fading trail from start → end with an arrowhead | ~800ms |
| text entry | highlight box around the field + caption of the typed text | ~800ms |
| inspect / point-at | highlight box around element bounds + label/id caption | ~1s |
| screenshot / snapshot | full-screen border pulse + tiny corner badge | ~300ms |

Color-coded: actions one hue, perception another. Concurrent effects capped
(oldest dropped) so a burst of actions cannot accumulate unbounded.

## Keeping it out of the agent's perception

- **Screenshot** (`screenshot_ext.dart`): the capture brackets `toImage` with
  `controller.beginCaptureSuppression()` → set the flag, settle one frame (the
  capture path already settles frames on retry, so this is ~free), capture, then
  `endCaptureSuppression()` in a `finally`. A screenshot's *own* flash effect is
  fired **after** suppression ends, so it is never in the captured bytes.
- **Snapshot** (`snapshot` walker): skips the sentinel-tagged overlay subtree.
  The host is `IgnorePointer` + `CustomPaint` with no semantics, but the skip
  rule is explicit rather than relying on incidental filtering.

## Control surface

- **On by default** whenever the probe is installed (already debug-only).
- Compile-time opt-out: `AgentWiresProbe.install(actionOverlay: false)`
  (defaults to `true`).
- Runtime toggle:
  - new probe extension **`ext.qa.set_overlay`** — `{enabled: bool}` → flips
    `controller.enabled`, returns the resulting state.
  - new MCP tool **`set_action_overlay(enabled)`** — calls `ext.qa.set_overlay`.
    Tool count 24 → **25**.
- Versions: probe `0.1.6 → 0.1.7`, mcp `0.1.5 → 0.1.6`; bump
  `recommendedProbeVersion` to `0.1.7`.

## TDD plan (test-first, every unit)

1. **Controller** (pure unit): push-when-enabled adds; push-when-disabled and
   push-when-suppressed are no-ops; `setEnabled(false)` clears active effects;
   the concurrent cap drops the oldest; expiry removes an effect.
2. **Host** (widget test in a `MaterialApp`): `showTap` paints an effect and it
   clears after its duration; `IgnorePointer` lets a button beneath still
   receive its tap; `suppressedForCapture` → `visibleEffects` empty.
3. **Installer** (widget test): finds the `Overlay` and inserts the entry; an app
   with no `Overlay` does not throw.
4. **Screenshot suppression**: a seam asserts the suppression flag is true
   *during* capture and false afterwards (even on capture failure).
5. **`ext.qa.set_overlay`**: `enabled:false` flips the controller and returns the
   state.
6. **MCP `set_action_overlay`**: invokes `ext.qa.set_overlay` with the param
   (mirrors existing tool tests).
7. **version_test**: probe version pin bumped to match `pubspec.yaml`.

## Files

New (probe):
- `lib/src/overlay/action_overlay_controller.dart`
- `lib/src/overlay/overlay_effect.dart`
- `lib/src/overlay/action_overlay_host.dart`
- `lib/src/overlay/action_overlay_installer.dart`
- `lib/src/extensions/set_overlay_ext.dart`

New (mcp):
- `set_action_overlay` tool (in `action_tools.dart` or a new `overlay_tools.dart`).

Wiring edits:
- `tap/long_press/swipe/scroll/press_back/enter_text/clear_text/inspect_ext` and
  the `label_element` resolve path each push an effect after success (they
  already compute the offset/rect).
- `snapshot_ext` / `screenshot_ext` fire a flash; `screenshot_ext` adds the
  suppression bracket.
- `probe.dart` registers `ext.qa.set_overlay` and threads the `actionOverlay`
  install flag.
- snapshot walker gets the sentinel skip rule.
- version files + CHANGELOGs for both packages; README tool-count/feature note.
