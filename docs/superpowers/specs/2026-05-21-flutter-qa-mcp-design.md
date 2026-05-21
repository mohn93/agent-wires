# Flutter QA MCP — Design

**Date:** 2026-05-21
**Status:** Draft (pending user review)
**Scope:** v1

## Summary

A Flutter SDK plus MCP server that exposes a running Flutter app's runtime widget tree to an LLM agent. The agent perceives the app through a denoised semantic tree (not screenshots, not the accessibility tree), takes actions through real gesture synthesis, and labels what it sees. A bundled web dashboard lets a human curate the agent's label proposals. Over time, the persistent semantic map turns the app's UI vocabulary into a first-class, queryable artifact — and the agent's per-step cost falls toward zero.

## Problem

QA agents that drive mobile apps autonomously have two bad options for perception:

- **Pure vision** (screenshots → VLM) is expensive per step and brittle on coordinate grounding.
- **Accessibility tree** is unreliable — most apps don't expose meaningful semantic labels.

Flutter makes both worse. The entire UI renders to a single Skia canvas; XCUITest and UIAutomator see one `FlutterView` and nothing useful inside it. OCR works but doesn't tell you what's tappable. So Flutter is exactly the case where external perception fails hardest.

It's also the case where **internal perception works best**, because Flutter exposes a rich runtime introspection surface (the Element/RenderObject tree, plus `creationLocation` source mapping in debug mode) that we can reach over the existing Dart VM service channel.

## Goals (v1)

1. An LLM agent, with no app-specific knowledge, can autonomously navigate any Flutter app in debug or profile mode and complete common QA flows.
2. Apps don't need to add test IDs, semantic labels, or any developer effort beyond a single `flutter pub add --dev flutter_qa_probe` and one line in `main()`.
3. A human can curate the agent's understanding of the app in ~30 minutes per week, and that curation compounds across future runs.
4. Snapshots fit in an LLM context window — denoised semantic tree, not raw widget tree.

## Non-goals (v1)

- Release-build QA. Debug/profile only.
- WebView support. Native Flutter only.
- State-management adapters (Riverpod/Bloc/Provider introspection).
- Network mocking / canned response replay.
- Multi-touch gestures (pinch, multi-finger drag).
- Cross-platform — iOS/Android Flutter both work for free via VM service, but native iOS/Android non-Flutter apps are out of scope.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  LLM Agent (any MCP client)                         │
└────────────────────────┬────────────────────────────┘
                         │ MCP protocol
                         ▼
┌─────────────────────────────────────────────────────┐
│  flutter-qa-mcp (MCP server, Node/TS or Dart)       │
│   - 16 tools (perception / action / sync / memory)  │
│   - denoiser (Element tree → semantic tree)         │
│   - persistent semantic map (.flutter_qa/map.json)  │
│   - bundled web review dashboard (localhost:7345)   │
└────────────────────────┬────────────────────────────┘
                         │ Dart VM Service (WebSocket)
                         ▼
┌─────────────────────────────────────────────────────┐
│  Flutter app (debug / profile mode)                 │
│   flutter_qa_probe (Dart package)                   │
│    - registers VM service extensions                │
│    - hooks WidgetsBinding, GestureBinding,          │
│      NavigatorObserver, SchedulerBinding            │
└─────────────────────────────────────────────────────┘
```

**Three pieces:**

1. **`flutter_qa_probe`** — Dart package, dev dependency. Single-line install:
   ```dart
   void main() {
     FlutterQAProbe.install();
     runApp(MyApp());
   }
   ```
   Registers VM service extensions for tree inspection, action injection, and lifecycle observation. Compiled out of release builds via Dart's `assert` / build-mode checks.

2. **`flutter-qa-mcp`** — Standalone MCP server. Attaches to a running app's VM service URI. Translates MCP tool calls into VM service extension calls. Owns the denoiser, the persistent semantic map, and the review dashboard.

3. **The agent** — any MCP client. Out of scope.

**Why VM service:** Flutter Inspector, DevTools, and Hot Reload all ride this channel. Battle-tested, available in debug+profile, supports attach-to-running-app rather than requiring a custom harness.

**Dev workflow:**
```bash
flutter run                                       # prints VM service URI
flutter-qa-mcp --attach <uri>                     # MCP server connects
# agent (configured to point at the MCP server) now has tools
flutter-qa-mcp review                             # opens dashboard at localhost:7345
```

**CI workflow:** `flutter test integration_test/<entry>.dart --machine` (or `flutter drive`) boots the app with a VM service URI; the MCP server attaches; the agent runs scripted or exploratory flows.

## MCP tool surface (16 tools)

### Perception
| Tool | Purpose |
|---|---|
| `snapshot()` | Denoised semantic tree of the visible screen. Primary tool — agent calls after every action. Returns `{route, viewport, elements[], unresolved[]}`. |
| `inspect(element_id)` | Full widget chain, properties, `creationLocation` for one element. For when `snapshot`'s summary isn't enough. |
| `screenshot(annotated?)` | PNG bytes. With `annotated=true`, overlays numbered Set-of-Mark boxes using current snapshot's element IDs. |

### Action
| Tool | Purpose |
|---|---|
| `tap(element_id)` | Synthesizes a real `PointerEvent` through `GestureBinding.handlePointerEvent`. Tests actual gesture wiring, not just `onPressed`. |
| `long_press(element_id, duration_ms?)` | Same path, held. |
| `enter_text(element_id, text)` | Focuses field, drives `TextInput.updateEditingValue`. |
| `clear_text(element_id)` | |
| `scroll(direction, element_id?, distance?)` | Drives nearest visible `Scrollable` or a specific one. |
| `swipe(from, to)` | Generic two-point gesture for carousels and custom swipes. |
| `press_back()` | Routes through `Navigator.maybePop`. |

### Sync
| Tool | Purpose |
|---|---|
| `wait_for_idle(timeout_ms?)` | Returns when no pending frames, no running animations, no in-flight HTTP. Replaces `sleep` polling. |
| `wait_for_route(predicate, timeout_ms?)` | Hooks `NavigatorObserver`. |
| `wait_for_element(predicate, timeout_ms?)` | Returns when a matching element appears. |

### Memory / teaching
| Tool | Purpose |
|---|---|
| `label_element(element_id, name, role?, notes?)` | Persists a label to the semantic map, keyed by element fingerprint. Used by agent (hypothesis) and human (correction). |
| `get_labels(route?)` | Returns persistent labels for a route. Automatically applied during `snapshot`. |
| `recall(query)` | Search the map by name/role across screens. |

### `snapshot()` output schema

```json
{
  "route": "/cart",
  "viewport": {"w": 390, "h": 844},
  "elements": [
    {
      "id": "e_a3f2k1",
      "fingerprint": "f_8c3d9a",
      "role": "button",
      "label": "Checkout",
      "label_source": "text_child",
      "persistent_label": "Primary CTA",
      "bounds": {"x": 120, "y": 580, "w": 240, "h": 48},
      "enabled": true,
      "widget_type": "ElevatedButton"
    }
  ],
  "unresolved": [
    {
      "id": "e_b9q4z",
      "fingerprint": "f_2k1m0c",
      "role": "tappable",
      "bounds": {"x": 320, "y": 56, "w": 32, "h": 32},
      "widget_type": "GestureDetector",
      "proposals": [
        {"source": "source_location", "label": "Cart", "confidence": 0.7}
      ]
    }
  ]
}
```

### Element ID and fingerprint

- **`id`** — opaque, per-snapshot. Stable within one snapshot; do not assume it survives across snapshots.
- **`fingerprint`** — stable across snapshots and runs of the same app version. Computed as `hash(creationLocation + widget_type + ancestor_type_path + sibling_index + visible_text_hash)`. This is the key into the persistent semantic map.

When `creationLocation` is unavailable (e.g., a release-mode probe — out of scope for v1 but the design accommodates), the fingerprint falls back to the ancestor-path components only.

## Denoiser

Walks the Element tree, classifies each node as **promote**, **skip**, or **collapse**.

**Promote** (becomes a `snapshot.elements[]` entry):
- Interactive widgets: `ElevatedButton`, `TextButton`, `OutlinedButton`, `IconButton`, `FloatingActionButton`, `TextField`, `TextFormField`, `Switch`, `Checkbox`, `Radio`, `Slider`, `DropdownButton`, `PopupMenuButton`
- Structural anchors: `AppBar`, `BottomNavigationBar`, individual `Tab`s, `Drawer`, `Dialog`, `BottomSheet`, `SnackBar`
- List items: `ListTile`, `Card` with `onTap`, children of `ListView` whose subtree contains a non-null handler
- Anything with a non-null gesture: `GestureDetector` / `InkWell` / `Listener` with `onTap`, `onLongPress`, `onDoubleTap`, etc.
- Anything wrapped in `Semantics` with a label or action
- Free-standing `Text` (headings, body) not attributed to a promoted ancestor

**Skip** (omitted, don't recurse-promote into output):
- Layout: `Padding`, `Center`, `Align`, `SizedBox`, `Container` without decoration or handler, `Expanded`, `Flexible`, `Row`, `Column`, `Stack`, `Wrap`, `ConstrainedBox`, `FractionallySizedBox`
- Theming/inheritance: `Theme`, `MediaQuery`, `DefaultTextStyle`, `IconTheme`, `Directionality`, bare `Material`
- Plumbing: `Builder`, `LayoutBuilder`, `AnimatedBuilder`, `ValueListenableBuilder`, `StreamBuilder` (children may still promote)

**Collapse:** descendant `Text` and `Icon` inside a promoted parent are rolled into the parent's `label` and `icon` fields, not emitted separately.

Expected reduction: ~800-node Element tree → 15–30 emitted elements per screen.

## Role inference (the "no semantics" answer)

For a promoted element with no explicit label, infer role from cheap signals in order:

1. **Descendant `Icon`** → look up `IconData.codePoint` in a static `MaterialIcons` / `CupertinoIcons` map. `Icons.shopping_cart` → "cart"; `Icons.delete` → "delete". This alone resolves ~40% of unlabeled buttons.
2. **Asset path** of descendant `Image` / `SvgPicture` — `assets/icons/cart.png` → "cart".
3. **Sibling text** in the same `Row`/`Column`/`Stack` — `IconButton` adjacent to a "3" badge → likely notifications/counter.
4. **Position context** — top-right of `AppBar` → "primary action"; bottom-right `FloatingActionButton` → "primary CTA".
5. **`creationLocation` + AST** — see below. The most powerful signal.

If none of the above produce a confident label, the element lands in `unresolved[]` with whatever proposals were generated.

## The Flutter superpower: `creationLocation`

Flutter ships with `--track-widget-creation` enabled in debug mode. **Every widget knows its source `file:line:column`.** Native iOS/Android don't have this.

Two uses:

1. **Stable fingerprint** — `cart_screen.dart:127:14` is the same logical widget every run, regardless of layout cruft above it. Becomes the persistent map key.
2. **Symbol-context naming** — a lightweight Dart AST parse of the source file extracts the enclosing function/method name. A `GestureDetector` at `cart_screen.dart:127` inside `_buildRemoveButton()` proposes `label="Remove"` with confidence 0.7 — without inspecting the closure body.

This is the trick that makes Flutter v1 work without per-step vision: source-location does what accessibility labels would have.

## Augmentation loop

Unresolved elements are labeling tasks the system actively works to close. Two proposal sources in v1:

| Source | When it fires | Typical confidence |
|---|---|---|
| `source_location` | Synchronous during `snapshot`. AST parse of the source file at the widget's `creationLocation` extracts the enclosing function name. | 0.5–0.8 |
| `vlm` | On-demand. Agent calls `screenshot(annotated=true)` and asks a VLM "what does element 7 likely do?" Result posted back via `label_element` with source=vlm. | 0.5–0.7 |

Deferred to v2: `network` proposals (observe HTTP traffic triggered by the action), `state_diff` proposals (diff the widget tree before/after).

Proposals accumulate in the persistent map keyed by fingerprint:

```json
{
  "fingerprint": "f_8c3d9a",
  "creation_location": "lib/cart/cart_screen.dart:127:14",
  "human_label": null,
  "proposals": [
    {"source": "source_location", "label": "Remove", "confidence": 0.7, "first_seen": "2026-05-21"},
    {"source": "vlm", "label": "Trash icon", "confidence": 0.6, "first_seen": "2026-05-21"}
  ],
  "screen_context": "/cart",
  "observation_count": 14
}
```

`snapshot()` exposes the highest-confidence non-human proposal as `label` until a human confirms; then `human_label` is ground truth and proposals stop appearing.

**Critical invariant:** never promote agent-generated proposals to ground truth without human confirmation. Otherwise the map drifts as the agent's wrong guesses get reused.

## Web review dashboard

Bundled with the MCP server. Launched via `flutter-qa-mcp review` → `http://localhost:7345`.

Shows:
- Unreviewed elements, sorted by impact (`observation_count × screens_present`)
- Per-element view: screenshot with the element highlighted, proposals listed with confidence, action history ("agent tapped this 8 times; 6 succeeded, 2 errored")
- One-click actions: accept top proposal / edit label / mark "decorative — ignore" / flag as bug ("this shouldn't be tappable")

**Compounding effect (the thesis):**
- Run 1: many unresolved, agent escalates to VLM often, ~60% of flows complete autonomously
- Human spends 20–30 minutes in the dashboard
- Run 2: most unresolved labeled; agent faster, cheaper, more accurate
- By run 10: ~90% of the app's vocabulary mapped; unresolved appear only when the app changes

The human never types a test ID into source code. They curate a vocabulary post-hoc with full visual context.

## Storage and team sharing

- Map stored at `.flutter_qa/map.json` (or `.flutter_qa/map.sqlite` if the project grows past ~5k entries)
- Committed to git — the semantic map is a QA artifact like fixtures
- Fingerprints survive in-file refactors (line numbers shift, but `creationLocation` is updated as part of `pub get` re-analysis); cross-file moves break them. Dashboard surfaces orphaned labels and offers migration.

## Security

The probe is debug/profile only — Dart's `kDebugMode` / `kProfileMode` checks compile the install path out of release. VM service ports are local by default; remote attach requires explicit `--host` flag.

## Out of scope for v1 (deferred)

- Release-mode probe (would require signed bridge + dev-flavor build)
- WebView introspection (separate JS bridge)
- State-management adapters (Riverpod, Bloc, Provider)
- Network mocking and replay
- `network` and `state_diff` proposal sources
- Multi-touch gestures
- Native iOS/Android non-Flutter apps

## Open questions / risks

1. **MCP server language** — Node/TS or Dart? Dart gets us closer to the VM service client libraries (`vm_service` package) and keeps the toolchain unified, but Node has the broader MCP ecosystem. **Tentative answer:** Dart, with the official `vm_service` package; revisit if MCP tooling friction emerges.
2. **`creationLocation` reliability in profile mode** — `--track-widget-creation` defaults to on in debug, off in profile. May need to require profile users to opt in. Verify during implementation.
3. **Fingerprint collisions** — `creationLocation` is per widget *constructor call*, not per logical element. A widget inside a `ListView.builder` shares the same `creationLocation` across all list items. Mitigation: include `sibling_index` and `visible_text_hash` in the fingerprint. Verify this is sufficient on real list-heavy screens.
4. **Map merge conflicts** — when two devs label the same fingerprint differently, git resolves textually but the result may be wrong. The dashboard should detect conflicts and prompt.
5. **Dashboard scope creep** — easy to balloon into a full QA platform. v1 dashboard is read-many, write-one: review unresolved, label or dismiss. Nothing else.
