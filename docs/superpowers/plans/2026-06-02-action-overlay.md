# Action Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw transient on-screen visuals (ripple at taps, trail for swipes/scrolls, highlight box for inspect/text, screen flash for screenshot/snapshot) so a human watching the app sees what the agent is doing — without those visuals ever appearing in the agent's own `screenshot`/`snapshot`.

**Architecture:** A widget-free `ActionOverlayController` singleton (a `ChangeNotifier`) holds a capped list of active `OverlayEffect`s. Each probe extension, after a successful action/perception, pushes an effect and lazily installs a single `IgnorePointer`-wrapped `ActionOverlayHost` into the app's topmost `Overlay`. The host animates one `CustomPaint` per effect and removes each when its animation completes. The host is wrapped in a sentinel `AgentWiresOverlayMarker` so the snapshot walker skips it, and the screenshot path suppresses the overlay for the single captured frame. A new `ext.qa.set_overlay` extension + `set_action_overlay` MCP tool toggle it at runtime; it is on by default.

**Tech Stack:** Dart, Flutter (`flutter/widgets`, `dart:developer` service extensions), `package:test` / `flutter_test`. Probe package = `agent_wires_probe` (Flutter, run with `flutter test`). MCP package = `agent_wires_mcp` (pure Dart, run with `dart test`).

**Important cross-cutting note — global singleton + test hygiene:** `ActionOverlayController.instance` and `ActionOverlayInstaller` are process-global statics (matching the codebase's static-extension style). Any test that drives a wired extension on a success path will push an effect and (in a widget test) start an `AnimationController`. Therefore **every test that triggers a success path must (a) `await tester.pumpAndSettle()` before returning to drain the one-shot animations, and (b) reset state in `tearDown`**:

```dart
tearDown(() {
  ActionOverlayController.instance.reset();
  ActionOverlayInstaller.reset();
});
```

This is repeated in each wiring task that touches an existing test file.

---

## File Structure

New (probe — `packages/agent_wires_probe/lib/src/overlay/`):
- `overlay_effect.dart` — sealed `OverlayEffect` types + `OverlayFlashKind` enum.
- `action_overlay_controller.dart` — the widget-free model singleton.
- `overlay_marker.dart` — `AgentWiresOverlayMarker` sentinel wrapper.
- `overlay_painters.dart` — `OverlayEffectPainter` (`CustomPainter`).
- `action_overlay_host.dart` — `ActionOverlayHost` stateful widget.
- `action_overlay_installer.dart` — locates the top `Overlay`, inserts the host.
- `overlay_geometry.dart` — `currentScreenSize()` for element-less effects.

New (probe extension):
- `lib/src/extensions/set_overlay_ext.dart` — `ext.qa.set_overlay`.

New (mcp):
- `lib/src/tools/overlay_tools.dart` — `set_action_overlay` tool.

Modified (probe): `extensions/{tap,long_press,swipe,scroll,press_back,enter_text,clear_text,inspect,snapshot,screenshot}_ext.dart`, `tree/walker.dart`, `probe.dart`, `lib/src/version.dart`, `pubspec.yaml`, `CHANGELOG.md`, `README.md`.

Modified (mcp): `bin/agent_wires_mcp.dart`, `lib/src/tools/memory_tools.dart`, `lib/src/version.dart`, `pubspec.yaml`, `CHANGELOG.md`, `README.md`.

---

## Task 1: OverlayEffect model

**Files:**
- Create: `packages/agent_wires_probe/lib/src/overlay/overlay_effect.dart`
- Test: `packages/agent_wires_probe/test/overlay/overlay_effect_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/painting.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TapEffect carries its point, longPress flag and a 600ms duration', () {
    final fx = TapEffect(id: 'a', point: const Offset(10, 20), longPress: true);
    expect(fx.point, const Offset(10, 20));
    expect(fx.longPress, isTrue);
    expect(fx.duration, const Duration(milliseconds: 600));
  });

  test('DragEffect carries from/to', () {
    final fx = DragEffect(id: 'b', from: Offset.zero, to: const Offset(5, 5));
    expect(fx.from, Offset.zero);
    expect(fx.to, const Offset(5, 5));
  });

  test('HighlightEffect carries bounds and optional label', () {
    final fx = HighlightEffect(
        id: 'c', bounds: const Rect.fromLTWH(0, 0, 30, 40), label: 'Submit');
    expect(fx.bounds.width, 30);
    expect(fx.label, 'Submit');
  });

  test('FlashEffect carries its kind', () {
    final fx = FlashEffect(id: 'd', kind: OverlayFlashKind.screenshot);
    expect(fx.kind, OverlayFlashKind.screenshot);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/agent_wires_probe && flutter test test/overlay/overlay_effect_test.dart`
Expected: FAIL — `overlay_effect.dart` does not exist / types undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/painting.dart';

/// Whole-screen perception events that get a brief flash.
enum OverlayFlashKind { screenshot, snapshot }

/// One transient on-screen effect drawn for a human watching the agent drive
/// the app. Self-describing geometry + an animation duration; the host owns
/// the animation and removes the effect when it completes.
sealed class OverlayEffect {
  OverlayEffect({required this.id, required this.duration});
  final String id;
  final Duration duration;
}

class TapEffect extends OverlayEffect {
  TapEffect({required super.id, required this.point, this.longPress = false})
      : super(duration: const Duration(milliseconds: 600));
  final Offset point;
  final bool longPress;
}

class DragEffect extends OverlayEffect {
  DragEffect({required super.id, required this.from, required this.to})
      : super(duration: const Duration(milliseconds: 800));
  final Offset from;
  final Offset to;
}

class HighlightEffect extends OverlayEffect {
  HighlightEffect({required super.id, required this.bounds, this.label})
      : super(duration: const Duration(milliseconds: 1000));
  final Rect bounds;
  final String? label;
}

class FlashEffect extends OverlayEffect {
  FlashEffect({required super.id, required this.kind})
      : super(duration: const Duration(milliseconds: 300));
  final OverlayFlashKind kind;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/agent_wires_probe && flutter test test/overlay/overlay_effect_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/overlay/overlay_effect.dart packages/agent_wires_probe/test/overlay/overlay_effect_test.dart
git commit -m "feat(probe): OverlayEffect model for action overlay"
```

---

## Task 2: ActionOverlayController (widget-free model)

**Files:**
- Create: `packages/agent_wires_probe/lib/src/overlay/action_overlay_controller.dart`
- Test: `packages/agent_wires_probe/test/overlay/action_overlay_controller_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/painting.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = ActionOverlayController.instance;
  setUp(c.reset);

  test('defaults: enabled, no effects, not suppressed', () {
    expect(c.enabled, isTrue);
    expect(c.effects, isEmpty);
    expect(c.suppressedForCapture, isFalse);
  });

  test('showTap adds a TapEffect at the point', () {
    c.showTap(const Offset(3, 4));
    expect(c.effects.single, isA<TapEffect>());
    expect((c.effects.single as TapEffect).point, const Offset(3, 4));
  });

  test('pushes are no-ops while disabled', () {
    c.setEnabled(false);
    c.showTap(Offset.zero);
    c.showFlash(kind: OverlayFlashKind.snapshot);
    expect(c.effects, isEmpty);
  });

  test('setEnabled(false) clears existing effects', () {
    c.showTap(Offset.zero);
    expect(c.effects, isNotEmpty);
    c.setEnabled(false);
    expect(c.effects, isEmpty);
  });

  test('the concurrent cap drops the oldest', () {
    for (var i = 0; i < ActionOverlayController.maxEffects + 3; i++) {
      c.showTap(Offset(i.toDouble(), 0));
    }
    expect(c.effects.length, ActionOverlayController.maxEffects);
    // oldest (x=0,1,2) dropped; first remaining is x=3.
    expect((c.effects.first as TapEffect).point.dx, 3);
  });

  test('suppression hides visibleEffects but keeps effects', () {
    c.showTap(Offset.zero);
    c.beginCaptureSuppression();
    expect(c.suppressedForCapture, isTrue);
    expect(c.visibleEffects, isEmpty);
    expect(c.effects, isNotEmpty);
    c.endCaptureSuppression();
    expect(c.visibleEffects, isNotEmpty);
  });

  test('removeEffect removes a specific effect', () {
    c.showTap(Offset.zero);
    final fx = c.effects.single;
    c.removeEffect(fx);
    expect(c.effects, isEmpty);
  });

  test('notifies listeners on change', () {
    var n = 0;
    void listener() => n++;
    c.addListener(listener);
    c.showTap(Offset.zero);
    c.removeListener(listener);
    expect(n, greaterThan(0));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/agent_wires_probe && flutter test test/overlay/action_overlay_controller_test.dart`
Expected: FAIL — controller does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'overlay_effect.dart';

/// Widget-free model holding the active on-screen effects. A process-global
/// singleton so static service-extension handlers can push to it without
/// threading a reference through every call. The host widget listens and
/// renders; the screenshot/snapshot paths read [suppressedForCapture] and
/// [visibleEffects] to keep the overlay out of the agent's perception.
class ActionOverlayController extends ChangeNotifier {
  ActionOverlayController._();
  static final ActionOverlayController instance = ActionOverlayController._();

  /// Most effects kept at once; a burst of actions cannot grow unbounded.
  static const int maxEffects = 12;

  bool _enabled = true;
  bool get enabled => _enabled;

  bool _suppressed = false;
  bool get suppressedForCapture => _suppressed;

  final List<OverlayEffect> _effects = <OverlayEffect>[];
  List<OverlayEffect> get effects => List.unmodifiable(_effects);

  /// The effects the host should paint right now — empty while a screenshot is
  /// being captured, so the overlay never lands in the captured pixels.
  List<OverlayEffect> get visibleEffects =>
      _suppressed ? const <OverlayEffect>[] : List.unmodifiable(_effects);

  int _seq = 0;
  String _nextId() => 'fx_${_seq++}';

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) _effects.clear();
    notifyListeners();
  }

  void beginCaptureSuppression() {
    if (_suppressed) return;
    _suppressed = true;
    notifyListeners();
  }

  void endCaptureSuppression() {
    if (!_suppressed) return;
    _suppressed = false;
    notifyListeners();
  }

  void showTap(Offset point, {bool longPress = false}) =>
      _add(TapEffect(id: _nextId(), point: point, longPress: longPress));

  void showDrag(Offset from, Offset to) =>
      _add(DragEffect(id: _nextId(), from: from, to: to));

  void showHighlight(Rect bounds, {String? label}) =>
      _add(HighlightEffect(id: _nextId(), bounds: bounds, label: label));

  void showFlash({required OverlayFlashKind kind}) =>
      _add(FlashEffect(id: _nextId(), kind: kind));

  void removeEffect(OverlayEffect effect) {
    if (_effects.remove(effect)) notifyListeners();
  }

  void _add(OverlayEffect effect) {
    if (!_enabled) return;
    _effects.add(effect);
    while (_effects.length > maxEffects) {
      _effects.removeAt(0);
    }
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _enabled = true;
    _suppressed = false;
    _effects.clear();
    _seq = 0;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/agent_wires_probe && flutter test test/overlay/action_overlay_controller_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/overlay/action_overlay_controller.dart packages/agent_wires_probe/test/overlay/action_overlay_controller_test.dart
git commit -m "feat(probe): ActionOverlayController model"
```

---

## Task 3: Marker, painters, and host widget

**Files:**
- Create: `packages/agent_wires_probe/lib/src/overlay/overlay_marker.dart`
- Create: `packages/agent_wires_probe/lib/src/overlay/overlay_painters.dart`
- Create: `packages/agent_wires_probe/lib/src/overlay/action_overlay_host.dart`
- Test: `packages/agent_wires_probe/test/overlay/action_overlay_host_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = ActionOverlayController.instance;
  setUp(c.reset);
  tearDown(c.reset);

  Widget host() => Directionality(
        textDirection: TextDirection.ltr,
        child: ActionOverlayHost(controller: c),
      );

  testWidgets('renders one keyed effect per active effect', (tester) async {
    await tester.pumpWidget(host());
    c.showTap(const Offset(20, 20));
    await tester.pump(); // let the host rebuild
    expect(find.byKey(const ValueKey('aw_effect_fx_0')), findsOneWidget);
  });

  testWidgets('effect is removed after its animation completes',
      (tester) async {
    await tester.pumpWidget(host());
    c.showTap(const Offset(20, 20));
    await tester.pump();
    expect(c.effects, isNotEmpty);
    await tester.pumpAndSettle(); // drain the 600ms animation
    expect(c.effects, isEmpty);
  });

  testWidgets('renders nothing while suppressed', (tester) async {
    await tester.pumpWidget(host());
    c.showTap(const Offset(20, 20));
    c.beginCaptureSuppression();
    await tester.pump();
    expect(find.byKey(const ValueKey('aw_effect_fx_0')), findsNothing);
    c.endCaptureSuppression();
    await tester.pumpAndSettle();
  });

  testWidgets('IgnorePointer lets a widget beneath still receive taps',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
          ActionOverlayHost(controller: c),
        ],
      ),
    ));
    c.showTap(const Offset(20, 20));
    await tester.pump();
    await tester.tapAt(const Offset(50, 50));
    expect(taps, 1);
    await tester.pumpAndSettle();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/agent_wires_probe && flutter test test/overlay/action_overlay_host_test.dart`
Expected: FAIL — host/marker/painter do not exist.

- [ ] **Step 3a: Create the marker**

`packages/agent_wires_probe/lib/src/overlay/overlay_marker.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Wraps the action-overlay layer. The snapshot walker checks for this widget
/// type and skips the subtree, so the overlay — which is only for a human
/// watching — never appears in what the agent perceives.
class AgentWiresOverlayMarker extends StatelessWidget {
  const AgentWiresOverlayMarker({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
```

- [ ] **Step 3b: Create the painters**

`packages/agent_wires_probe/lib/src/overlay/overlay_painters.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'overlay_effect.dart';

/// Paints a single [OverlayEffect], repainting as its [anim] advances 0→1.
class OverlayEffectPainter extends CustomPainter {
  OverlayEffectPainter(this.effect, this.anim) : super(repaint: anim);
  final OverlayEffect effect;
  final Animation<double> anim;

  static const Color _action = Color(0xFF00E5FF); // touch actions
  static const Color _perception = Color(0xFFFFC107); // look / point-at

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static Color _fade(Color c, double o) =>
      c.withAlpha((255 * o.clamp(0.0, 1.0)).round());

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    switch (effect) {
      case TapEffect(:final point, :final longPress):
        _tap(canvas, point, t, longPress);
      case DragEffect(:final from, :final to):
        _drag(canvas, from, to, t);
      case HighlightEffect(:final bounds, :final label):
        _highlight(canvas, bounds, label, t);
      case FlashEffect(:final kind):
        _flash(canvas, size, kind, t);
    }
  }

  void _tap(Canvas canvas, Offset p, double t, bool longPress) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = _fade(_action, 1 - t);
    canvas.drawCircle(p, _lerp(8, 46, t), ring);
    canvas.drawCircle(p, 8, Paint()..color = _fade(_action, 0.8 * (1 - t)));
    if (longPress) {
      canvas.drawCircle(
          p, _lerp(4, 22, t), Paint()..color = _fade(_action, 0.35 * (1 - t)));
    }
  }

  void _drag(Canvas canvas, Offset from, Offset to, double t) {
    final head = Offset.lerp(from, to, t)!;
    final line = Paint()
      ..color = _fade(_action, 1 - t)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, head, line);
    canvas.drawCircle(head, 6, Paint()..color = _fade(_action, 1 - t));
  }

  void _highlight(Canvas canvas, Rect bounds, String? label, double t) {
    final rrect =
        RRect.fromRectAndRadius(bounds.inflate(2), const Radius.circular(6));
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _fade(_perception, 1 - 0.3 * t));
    canvas.drawRRect(rrect, Paint()..color = _fade(_perception, 0.12 * (1 - t)));
    if (label != null && label.isNotEmpty) {
      _caption(canvas, label, bounds.topLeft, _perception, 1 - t);
    }
  }

  void _flash(Canvas canvas, Size size, OverlayFlashKind kind, double t) {
    final color = kind == OverlayFlashKind.screenshot ? _perception : _action;
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _lerp(10, 2, t)
          ..color = _fade(color, 0.9 * (1 - t)));
    final tag = kind == OverlayFlashKind.screenshot ? 'screenshot' : 'snapshot';
    _caption(canvas, tag, const Offset(8, 8), color, 1 - t);
  }

  void _caption(
      Canvas canvas, String text, Offset at, Color color, double opacity) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11,
          color: _fade(const Color(0xFF000000), opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = const Offset(4, 2);
    final bg = Rect.fromLTWH(
        at.dx, at.dy, tp.width + pad.dx * 2, tp.height + pad.dy * 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(bg, const Radius.circular(3)),
        Paint()..color = _fade(color, opacity));
    tp.paint(canvas, at + pad);
  }

  @override
  bool shouldRepaint(OverlayEffectPainter old) => old.effect != effect;
}
```

- [ ] **Step 3c: Create the host**

`packages/agent_wires_probe/lib/src/overlay/action_overlay_host.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'action_overlay_controller.dart';
import 'overlay_marker.dart';
import 'overlay_painters.dart';

/// Renders the active overlay effects above the app. Wrapped in
/// [AgentWiresOverlayMarker] (so snapshot skips it) and [IgnorePointer] (so it
/// never steals input). Owns one [AnimationController] per effect and removes
/// each effect from the controller when its animation completes.
class ActionOverlayHost extends StatefulWidget {
  const ActionOverlayHost({super.key, required this.controller});
  final ActionOverlayController controller;
  @override
  State<ActionOverlayHost> createState() => _ActionOverlayHostState();
}

class _ActionOverlayHostState extends State<ActionOverlayHost>
    with TickerProviderStateMixin {
  final Map<String, AnimationController> _anims = {};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _sync();
  }

  void _onChange() {
    if (!mounted) return;
    setState(_sync);
  }

  void _sync() {
    for (final fx in widget.controller.effects) {
      _anims.putIfAbsent(fx.id, () {
        final ac = AnimationController(vsync: this, duration: fx.duration)
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed) {
              widget.controller.removeEffect(fx);
            }
          });
        ac.forward();
        return ac;
      });
    }
    final live = widget.controller.effects.map((e) => e.id).toSet();
    for (final id in _anims.keys.where((k) => !live.contains(k)).toList()) {
      _anims.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    for (final ac in _anims.values) {
      ac.dispose();
    }
    _anims.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AgentWiresOverlayMarker(
      child: IgnorePointer(
        child: Stack(
          children: [
            for (final fx in widget.controller.visibleEffects)
              if (_anims[fx.id] != null)
                Positioned.fill(
                  key: ValueKey('aw_effect_${fx.id}'),
                  child: CustomPaint(
                    painter: OverlayEffectPainter(fx, _anims[fx.id]!),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/agent_wires_probe && flutter test test/overlay/action_overlay_host_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/overlay/overlay_marker.dart packages/agent_wires_probe/lib/src/overlay/overlay_painters.dart packages/agent_wires_probe/lib/src/overlay/action_overlay_host.dart packages/agent_wires_probe/test/overlay/action_overlay_host_test.dart
git commit -m "feat(probe): ActionOverlayHost + painters + marker"
```

---

## Task 4: ActionOverlayInstaller

**Files:**
- Create: `packages/agent_wires_probe/lib/src/overlay/action_overlay_installer.dart`
- Test: `packages/agent_wires_probe/test/overlay/action_overlay_installer_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_installer.dart';
import 'package:agent_wires_probe/src/overlay/overlay_marker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    ActionOverlayController.instance.reset();
    ActionOverlayInstaller.reset();
  });
  tearDown(() {
    ActionOverlayController.instance.reset();
    ActionOverlayInstaller.reset();
  });

  testWidgets('inserts the host into a MaterialApp overlay', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    expect(ActionOverlayInstaller.ensureInstalled(), isTrue);
    await tester.pump();
    expect(find.byType(AgentWiresOverlayMarker), findsOneWidget);
  });

  testWidgets('is idempotent — calling twice inserts one host', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    ActionOverlayInstaller.ensureInstalled();
    ActionOverlayInstaller.ensureInstalled();
    await tester.pump();
    expect(find.byType(AgentWiresOverlayMarker), findsOneWidget);
  });

  testWidgets('no Overlay present → returns false, does not throw',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Text('no overlay here'),
    ));
    expect(ActionOverlayInstaller.ensureInstalled(), isFalse);
    await tester.pump();
    expect(find.byType(AgentWiresOverlayMarker), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/agent_wires_probe && flutter test test/overlay/action_overlay_installer_test.dart`
Expected: FAIL — installer does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/widgets.dart';
import 'action_overlay_controller.dart';
import 'action_overlay_host.dart';

/// Lazily inserts the single [ActionOverlayHost] into the app's topmost
/// [Overlay]. Idempotent and structure-independent: if no Overlay exists yet
/// (before the first frame, or an app with no Navigator) it returns false and
/// a later call retries.
class ActionOverlayInstaller {
  static OverlayEntry? _entry;

  static bool ensureInstalled() {
    if (_entry != null) return true;
    final overlay = _findOverlayState();
    if (overlay == null) return false;
    final entry = OverlayEntry(
      builder: (_) =>
          ActionOverlayHost(controller: ActionOverlayController.instance),
    );
    overlay.insert(entry);
    _entry = entry;
    return true;
  }

  static OverlayState? _findOverlayState() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    OverlayState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is OverlayState) {
        found = e.state as OverlayState;
        return;
      }
      e.visitChildren(visit);
    }
    visit(root);
    return found;
  }

  @visibleForTesting
  static void reset() {
    _entry?.remove();
    _entry = null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/agent_wires_probe && flutter test test/overlay/action_overlay_installer_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/overlay/action_overlay_installer.dart packages/agent_wires_probe/test/overlay/action_overlay_installer_test.dart
git commit -m "feat(probe): ActionOverlayInstaller — lazy overlay insertion"
```

---

## Task 5: ext.qa.set_overlay extension

**Files:**
- Create: `packages/agent_wires_probe/lib/src/extensions/set_overlay_ext.dart`
- Test: `packages/agent_wires_probe/test/extensions/set_overlay_ext_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'package:agent_wires_probe/src/extensions/set_overlay_ext.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = ActionOverlayController.instance;
  setUp(c.reset);

  test('enabled:false disables the controller and echoes state', () async {
    final resp = await SetOverlayExtension.handle(
        'ext.qa.set_overlay', {'enabled': 'false'});
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(body['enabled'], isFalse);
    expect(c.enabled, isFalse);
  });

  test('enabled:true re-enables the controller', () async {
    c.setEnabled(false);
    await SetOverlayExtension.handle('ext.qa.set_overlay', {'enabled': 'true'});
    expect(c.enabled, isTrue);
  });

  test('missing enabled returns success:false', () async {
    final resp =
        await SetOverlayExtension.handle('ext.qa.set_overlay', const {});
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/set_overlay_ext_test.dart`
Expected: FAIL — extension does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'dart:convert';
import 'dart:developer' as developer;
import '../overlay/action_overlay_controller.dart';

class SetOverlayExtension {
  static const String name = 'ext.qa.set_overlay';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final raw = params['enabled'];
    if (raw == null) {
      return _ok({'success': false, 'error': 'enabled required'});
    }
    final enabled = raw == 'true';
    ActionOverlayController.instance.setEnabled(enabled);
    return _ok({'success': true, 'enabled': enabled});
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/set_overlay_ext_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/extensions/set_overlay_ext.dart packages/agent_wires_probe/test/extensions/set_overlay_ext_test.dart
git commit -m "feat(probe): ext.qa.set_overlay extension"
```

---

## Task 6: Register extension + actionOverlay install flag

**Files:**
- Modify: `packages/agent_wires_probe/lib/src/probe.dart`
- Test: `packages/agent_wires_probe/test/probe_overlay_install_test.dart`

Note: `AgentWiresProbe.install` is process-once (guarded by `_installed`). This test lives in its own file so it runs in a fresh isolate with clean statics, letting us assert the `actionOverlay: false` path applies.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:agent_wires_probe/agent_wires_probe.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('install(actionOverlay:false) registers set_overlay and disables it',
      () {
    AgentWiresProbe.install(actionOverlay: false);
    expect(AgentWiresProbe.registeredExtensions, contains('ext.qa.set_overlay'));
    expect(ActionOverlayController.instance.enabled, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/agent_wires_probe && flutter test test/probe_overlay_install_test.dart`
Expected: FAIL — `install` has no `actionOverlay` parameter; extension not registered.

- [ ] **Step 3: Write minimal implementation**

In `packages/agent_wires_probe/lib/src/probe.dart`, add imports near the other extension imports:

```dart
import 'extensions/set_overlay_ext.dart';
import 'overlay/action_overlay_controller.dart';
```

Change the `install` signature and body. Replace:

```dart
  static void install() {
    if (_installed) return;
    if (kReleaseMode) return;
    _installed = true;
    HttpInflightTracker.install();
```

with:

```dart
  static void install({bool actionOverlay = true}) {
    if (_installed) return;
    if (kReleaseMode) return;
    _installed = true;
    ActionOverlayController.instance.setEnabled(actionOverlay);
    HttpInflightTracker.install();
```

And register the extension alongside the others (after the `GetNetworkExtension` line):

```dart
    _register(GetNetworkExtension.name, GetNetworkExtension.handle);
    _register(SetOverlayExtension.name, SetOverlayExtension.handle);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/agent_wires_probe && flutter test test/probe_overlay_install_test.dart`
Expected: PASS (1 test).

Also confirm the existing probe test still passes:
Run: `cd packages/agent_wires_probe && flutter test test/probe_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/probe.dart packages/agent_wires_probe/test/probe_overlay_install_test.dart
git commit -m "feat(probe): register set_overlay + actionOverlay install flag"
```

---

## Task 7: Wire tap + long_press

**Files:**
- Modify: `packages/agent_wires_probe/lib/src/extensions/tap_ext.dart`
- Modify: `packages/agent_wires_probe/lib/src/extensions/long_press_ext.dart`
- Test: `packages/agent_wires_probe/test/extensions/tap_ext_test.dart` (extend)
- Test: `packages/agent_wires_probe/test/extensions/long_press_ext_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

Add to `tap_ext_test.dart` — first add the import and a `tearDown`, then a new test:

```dart
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_installer.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
```

```dart
  tearDown(() {
    ActionOverlayController.instance.reset();
    ActionOverlayInstaller.reset();
  });

  testWidgets('a successful tap pushes a TapEffect at the tap point',
      (tester) async {
    ActionOverlayController.instance.reset();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () {}, child: const Text('Press')),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      final resp =
          await TapExtension.handle('ext.qa.tap', {'element_id': 'e_$i'});
      if (jsonDecode(resp.result!)['success'] == true) break;
    }
    expect(ActionOverlayController.instance.effects.whereType<TapEffect>(),
        isNotEmpty);
    expect(ActionOverlayController.instance.effects.first, isA<TapEffect>());
    await tester.pumpAndSettle();
  });
```

Add to `long_press_ext_test.dart` (read the existing file first to match its harness; mirror its success-path setup) a test asserting a `TapEffect` with `longPress == true` is pushed after a successful long press, with the same `tearDown` + imports as above.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/tap_ext_test.dart test/extensions/long_press_ext_test.dart`
Expected: FAIL — no effect pushed (controller stays empty).

- [ ] **Step 3: Write minimal implementation**

In `tap_ext.dart`, add imports:

```dart
import '../overlay/action_overlay_controller.dart';
import '../overlay/action_overlay_installer.dart';
```

Replace the success block:

```dart
    try {
      await GestureSynth.tapAt(center);
      return _ok({'success': true, 'at': {'x': center.dx, 'y': center.dy}});
```

with:

```dart
    try {
      await GestureSynth.tapAt(center);
      ActionOverlayController.instance.showTap(center);
      ActionOverlayInstaller.ensureInstalled();
      return _ok({'success': true, 'at': {'x': center.dx, 'y': center.dy}});
```

In `long_press_ext.dart`, add the same two imports, and replace:

```dart
    try {
      await GestureSynth.longPressAt(center, hold: Duration(milliseconds: ms));
      return _ok({'success': true});
```

with:

```dart
    try {
      await GestureSynth.longPressAt(center, hold: Duration(milliseconds: ms));
      ActionOverlayController.instance.showTap(center, longPress: true);
      ActionOverlayInstaller.ensureInstalled();
      return _ok({'success': true});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/tap_ext_test.dart test/extensions/long_press_ext_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/extensions/tap_ext.dart packages/agent_wires_probe/lib/src/extensions/long_press_ext.dart packages/agent_wires_probe/test/extensions/tap_ext_test.dart packages/agent_wires_probe/test/extensions/long_press_ext_test.dart
git commit -m "feat(probe): tap/long_press draw an action-overlay ripple"
```

---

## Task 8: Screen geometry helper + wire swipe + scroll + press_back

**Files:**
- Create: `packages/agent_wires_probe/lib/src/overlay/overlay_geometry.dart`
- Modify: `packages/agent_wires_probe/lib/src/extensions/swipe_ext.dart`
- Modify: `packages/agent_wires_probe/lib/src/extensions/scroll_ext.dart`
- Modify: `packages/agent_wires_probe/lib/src/extensions/press_back_ext.dart`
- Test: `packages/agent_wires_probe/test/extensions/swipe_ext_test.dart` (extend)
- Test: `packages/agent_wires_probe/test/extensions/scroll_ext_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

Add to `swipe_ext_test.dart` (with the overlay imports + `tearDown` reset shown in Task 7):

```dart
  testWidgets('a successful swipe pushes a DragEffect from→to', (tester) async {
    ActionOverlayController.instance.reset();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    await SwipeExtension.handle('ext.qa.swipe', {
      'from_x': '10', 'from_y': '20', 'to_x': '10', 'to_y': '120',
    });
    final fx = ActionOverlayController.instance.effects
        .whereType<DragEffect>()
        .single;
    expect(fx.from, const Offset(10, 20));
    expect(fx.to, const Offset(10, 120));
    await tester.pumpAndSettle();
  });
```

Add to `scroll_ext_test.dart` (with the same imports + reset) a test that after a successful `scroll` (`direction: 'down'`) on a scrollable list, `effects.whereType<DragEffect>()` is non-empty. Read the existing `scroll_ext_test.dart` first to reuse its scrollable-list setup; assert only that a `DragEffect` was pushed (coordinates are screen-derived, so don't assert exact values).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/swipe_ext_test.dart test/extensions/scroll_ext_test.dart`
Expected: FAIL — no DragEffect pushed.

- [ ] **Step 3: Write minimal implementation**

Create `overlay_geometry.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Logical size of the app's primary view, for effects that have no element to
/// anchor to (scroll, press_back). Falls back to a sane default before a view
/// is available.
Size currentScreenSize() {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) return const Size(400, 800);
  return view.physicalSize / view.devicePixelRatio;
}

/// Unit vector for a named scroll/back direction in screen space.
Offset directionVector(String direction) => switch (direction) {
      'up' => const Offset(0, -1),
      'down' => const Offset(0, 1),
      'left' => const Offset(-1, 0),
      'right' => const Offset(1, 0),
      _ => Offset.zero,
    };
```

In `swipe_ext.dart`, add the overlay imports (controller + installer), and in the success branch after `await GestureSynth.swipe(...)`:

```dart
      await GestureSynth.swipe(
        Offset(fromX, fromY),
        Offset(toX, toY),
        duration: Duration(milliseconds: ms),
      );
      ActionOverlayController.instance
          .showDrag(Offset(fromX, fromY), Offset(toX, toY));
      ActionOverlayInstaller.ensureInstalled();
      return _ok({'success': true});
```

In `scroll_ext.dart`, add imports (controller, installer, `../overlay/overlay_geometry.dart`). Replace the success return:

```dart
      if (!ok) {
        return _ok({'success': false, 'error': 'no scrollable found or axis mismatch'});
      }
      return _ok({'success': true});
```

with:

```dart
      if (!ok) {
        return _ok({'success': false, 'error': 'no scrollable found or axis mismatch'});
      }
      final size = currentScreenSize();
      final center = Offset(size.width / 2, size.height / 2);
      final to = center +
          directionVector(direction.name) * distance.clamp(40, 200).toDouble();
      ActionOverlayController.instance.showDrag(center, to);
      ActionOverlayInstaller.ensureInstalled();
      return _ok({'success': true});
```

Note: `direction` is a `ScrollDir` enum; `direction.name` yields `'up'|'down'|'left'|'right'`, matching `directionVector`.

In `press_back_ext.dart`, read the file first, then on the success path push a back-indicator drag from the left edge inward and `ensureInstalled()`:

```dart
import '../overlay/action_overlay_controller.dart';
import '../overlay/action_overlay_installer.dart';
import '../overlay/overlay_geometry.dart';
```

After the navigator pop succeeds (mirror the file's existing success return):

```dart
      final size = currentScreenSize();
      ActionOverlayController.instance.showDrag(
          Offset(12, size.height / 2), Offset(size.width * 0.45, size.height / 2));
      ActionOverlayInstaller.ensureInstalled();
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/swipe_ext_test.dart test/extensions/scroll_ext_test.dart test/extensions/press_back_ext_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/overlay/overlay_geometry.dart packages/agent_wires_probe/lib/src/extensions/swipe_ext.dart packages/agent_wires_probe/lib/src/extensions/scroll_ext.dart packages/agent_wires_probe/lib/src/extensions/press_back_ext.dart packages/agent_wires_probe/test/extensions/swipe_ext_test.dart packages/agent_wires_probe/test/extensions/scroll_ext_test.dart
git commit -m "feat(probe): swipe/scroll/press_back draw a drag trail"
```

---

## Task 9: Wire enter_text + clear_text (field highlight)

**Files:**
- Modify: `packages/agent_wires_probe/lib/src/extensions/enter_text_ext.dart`
- Modify: `packages/agent_wires_probe/lib/src/extensions/clear_text_ext.dart`
- Test: `packages/agent_wires_probe/test/extensions/enter_text_ext_test.dart` (extend)
- Test: `packages/agent_wires_probe/test/extensions/clear_text_ext_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

Read both existing test files first to reuse their TextField setup. Add the overlay imports + `tearDown` reset (from Task 7). For `enter_text`, add:

```dart
  testWidgets('a successful enter_text highlights the field with the text',
      (tester) async {
    ActionOverlayController.instance.reset();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TextField()),
    ));
    for (var i = 0; i < 20; i++) {
      final resp = await EnterTextExtension.handle('ext.qa.enter_text',
          {'element_id': 'e_$i', 'text': 'hello'});
      if (jsonDecode(resp.result!)['success'] == true) break;
    }
    final fx = ActionOverlayController.instance.effects
        .whereType<HighlightEffect>()
        .singleOrNull;
    expect(fx, isNotNull);
    expect(fx!.label, 'hello');
    await tester.pumpAndSettle();
  });
```

For `clear_text`, add the analogous test asserting a `HighlightEffect` is pushed (label `'(cleared)'`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/enter_text_ext_test.dart test/extensions/clear_text_ext_test.dart`
Expected: FAIL — no HighlightEffect pushed.

- [ ] **Step 3: Write minimal implementation**

In `enter_text_ext.dart`, add imports:

```dart
import 'package:flutter/rendering.dart';
import '../overlay/action_overlay_controller.dart';
import '../overlay/action_overlay_installer.dart';
```

Replace the success branch:

```dart
    try {
      await TextInputDriver.setText(element, text);
      return _ok({'success': true});
```

with:

```dart
    try {
      await TextInputDriver.setText(element, text);
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize && ro.attached) {
        ActionOverlayController.instance.showHighlight(
            ro.localToGlobal(Offset.zero) & ro.size,
            label: text);
        ActionOverlayInstaller.ensureInstalled();
      }
      return _ok({'success': true});
```

In `clear_text_ext.dart`, read the file first, add the same imports, and on its success path push:

```dart
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize && ro.attached) {
        ActionOverlayController.instance.showHighlight(
            ro.localToGlobal(Offset.zero) & ro.size,
            label: '(cleared)');
        ActionOverlayInstaller.ensureInstalled();
      }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/enter_text_ext_test.dart test/extensions/clear_text_ext_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/extensions/enter_text_ext.dart packages/agent_wires_probe/lib/src/extensions/clear_text_ext.dart packages/agent_wires_probe/test/extensions/enter_text_ext_test.dart packages/agent_wires_probe/test/extensions/clear_text_ext_test.dart
git commit -m "feat(probe): enter_text/clear_text highlight the target field"
```

---

## Task 10: Wire inspect (point-at highlight)

**Files:**
- Modify: `packages/agent_wires_probe/lib/src/extensions/inspect_ext.dart`
- Test: `packages/agent_wires_probe/test/extensions/inspect_ext_test.dart` (extend)

- [ ] **Step 1: Write the failing test**

Read `inspect_ext_test.dart` first to reuse its element-resolution harness. Add the overlay imports + `tearDown` reset, then:

```dart
  testWidgets('a successful inspect highlights the element bounds',
      (tester) async {
    ActionOverlayController.instance.reset();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () {}, child: const Text('Go')),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      final resp = await InspectExtension.handle('ext.qa.inspect',
          {'element_id': 'e_$i', 'include_descendants': 'false'});
      if (resp.result != null) break;
    }
    expect(ActionOverlayController.instance.effects.whereType<HighlightEffect>(),
        isNotEmpty);
    await tester.pumpAndSettle();
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/inspect_ext_test.dart`
Expected: FAIL — no HighlightEffect pushed.

- [ ] **Step 3: Write minimal implementation**

In `inspect_ext.dart`, add imports:

```dart
import 'package:flutter/rendering.dart';
import '../overlay/action_overlay_controller.dart';
import '../overlay/action_overlay_installer.dart';
```

After the line that reads `final w = element.widget;` (before building props), add:

```dart
    final ro = element.renderObject;
    if (ro is RenderBox && ro.hasSize && ro.attached) {
      ActionOverlayController.instance.showHighlight(
          ro.localToGlobal(Offset.zero) & ro.size,
          label: w.runtimeType.toString());
      ActionOverlayInstaller.ensureInstalled();
    }
```

Note: `package:flutter/widgets.dart` is already imported in `inspect_ext.dart`, which re-exports `RenderBox`; the explicit `rendering.dart` import is harmless and keeps intent clear.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/inspect_ext_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/extensions/inspect_ext.dart packages/agent_wires_probe/test/extensions/inspect_ext_test.dart
git commit -m "feat(probe): inspect highlights the pointed-at element"
```

---

## Task 11: Snapshot walker skips the overlay

**Files:**
- Modify: `packages/agent_wires_probe/lib/src/tree/walker.dart`
- Test: `packages/agent_wires_probe/test/tree/walker_overlay_skip_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/overlay/overlay_marker.dart';
import 'package:agent_wires_probe/src/tree/walker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the overlay subtree is excluded from the walk', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Text('app-content'),
            AgentWiresOverlayMarker(child: Text('aw-overlay-canary')),
          ],
        ),
      ),
    ));
    final nodes = ElementTreeWalker.walkFromRoot();
    expect(nodes.any((n) => n.visibleText == 'app-content'), isTrue);
    expect(nodes.any((n) => n.visibleText == 'aw-overlay-canary'), isFalse);
    expect(
        nodes.any((n) => n.widgetType == 'AgentWiresOverlayMarker'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/agent_wires_probe && flutter test test/tree/walker_overlay_skip_test.dart`
Expected: FAIL — the canary text and marker appear in the walk.

- [ ] **Step 3: Write minimal implementation**

In `walker.dart`, add the import:

```dart
import '../overlay/overlay_marker.dart';
```

At the very top of the `visit` closure body (before the `inspector.toId` line), add the skip guard:

```dart
      void visit(Element e, int depth, int siblingIndex) {
        if (e.widget is AgentWiresOverlayMarker) return;
        // ignore: invalid_use_of_protected_member - WidgetInspectorService.toId is protected but has no public equivalent
        final id = inspector.toId(e, group);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/agent_wires_probe && flutter test test/tree/walker_overlay_skip_test.dart`
Expected: PASS.

Also re-run the existing walker test to confirm no regression:
Run: `cd packages/agent_wires_probe && flutter test test/tree/walker_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/tree/walker.dart packages/agent_wires_probe/test/tree/walker_overlay_skip_test.dart
git commit -m "feat(probe): snapshot walker skips the action-overlay subtree"
```

---

## Task 12: Snapshot flash + screenshot flash + capture suppression

**Files:**
- Modify: `packages/agent_wires_probe/lib/src/extensions/snapshot_ext.dart`
- Modify: `packages/agent_wires_probe/lib/src/extensions/screenshot_ext.dart`
- Test: `packages/agent_wires_probe/test/extensions/snapshot_ext_test.dart` (extend)
- Test: `packages/agent_wires_probe/test/extensions/screenshot_suppression_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `snapshot_ext_test.dart` (overlay imports + `tearDown` reset):

```dart
  testWidgets('snapshot pushes a snapshot FlashEffect', (tester) async {
    ActionOverlayController.instance.reset();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    await SnapshotExtension.handle('ext.qa.snapshot', const {});
    final flashes =
        ActionOverlayController.instance.effects.whereType<FlashEffect>();
    expect(flashes.single.kind, OverlayFlashKind.snapshot);
    await tester.pumpAndSettle();
  });
```

Create `screenshot_suppression_test.dart` for the suppression bracket:

```dart
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/screenshot_ext.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = ActionOverlayController.instance;
  setUp(c.reset);
  tearDown(c.reset);

  testWidgets('overlay is suppressed during the body, restored after',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    bool wasSuppressedDuring = false;
    final result = await ScreenshotExtension.captureWithOverlaySuppressed(
        () async {
      wasSuppressedDuring = c.suppressedForCapture;
      return 42;
    });
    expect(result, 42);
    expect(wasSuppressedDuring, isTrue);
    expect(c.suppressedForCapture, isFalse);
  });

  testWidgets('suppression is restored even if the body throws',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    await expectLater(
      ScreenshotExtension.captureWithOverlaySuppressed<void>(
          () async => throw StateError('boom')),
      throwsStateError,
    );
    expect(c.suppressedForCapture, isFalse);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/snapshot_ext_test.dart test/extensions/screenshot_suppression_test.dart`
Expected: FAIL — flash not pushed; `captureWithOverlaySuppressed` undefined.

- [ ] **Step 3: Write minimal implementation**

In `snapshot_ext.dart`, add imports:

```dart
import '../overlay/action_overlay_controller.dart';
import '../overlay/action_overlay_installer.dart';
import '../overlay/overlay_effect.dart';
```

Replace the success branch:

```dart
      final snap = SnapshotBuilder.build();
      return developer.ServiceExtensionResponse.result(jsonEncode(snap.toJson()));
```

with:

```dart
      final snap = SnapshotBuilder.build();
      ActionOverlayController.instance
          .showFlash(kind: OverlayFlashKind.snapshot);
      ActionOverlayInstaller.ensureInstalled();
      return developer.ServiceExtensionResponse.result(jsonEncode(snap.toJson()));
```

In `screenshot_ext.dart`, add imports:

```dart
import '../overlay/action_overlay_controller.dart';
import '../overlay/action_overlay_installer.dart';
import '../overlay/overlay_effect.dart';
```

Add the public suppression bracket (place it as a static method on `ScreenshotExtension`, e.g. just above `_capture`):

```dart
  /// Runs [body] (the rasterization) with the action overlay hidden, so the
  /// human-only overlay never lands in the captured pixels. Settles one frame
  /// after hiding it so the empty overlay is actually painted before capture,
  /// and always restores visibility — even on failure.
  static Future<T> captureWithOverlaySuppressed<T>(
      Future<T> Function() body) async {
    final c = ActionOverlayController.instance;
    c.beginCaptureSuppression();
    try {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame
          .timeout(const Duration(seconds: 1));
      return await body();
    } finally {
      c.endCaptureSuppression();
    }
  }
```

Wrap the existing capture call. Replace:

```dart
      final image = await _capture(boundary);
```

with:

```dart
      final image = await captureWithOverlaySuppressed(() => _capture(boundary));
```

And fire the screenshot flash after the bytes are encoded — replace the success return:

```dart
      final b64 = base64Encode(bytes.buffer.asUint8List());
      return developer.ServiceExtensionResponse.result(jsonEncode({
        'format': 'png',
        'width': image.width,
        'height': image.height,
        'data_base64': b64,
      }));
```

with:

```dart
      final b64 = base64Encode(bytes.buffer.asUint8List());
      // After suppression has ended, so the flash is never in the bytes above.
      ActionOverlayController.instance
          .showFlash(kind: OverlayFlashKind.screenshot);
      ActionOverlayInstaller.ensureInstalled();
      return developer.ServiceExtensionResponse.result(jsonEncode({
        'format': 'png',
        'width': image.width,
        'height': image.height,
        'data_base64': b64,
      }));
```

Note: `endOfFrame.timeout(...)` returns `Future<void>`; on timeout it throws `TimeoutException`, but it sits inside the `try` whose `finally` restores suppression. To keep the safety-net behaviour from being fatal, the surrounding `handle` already wraps everything in a `try/catch (e)` that returns an error response — acceptable. (A wedged engine producing no frames is the only path here, the same edge the existing `_settleFrame` tolerates.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/agent_wires_probe && flutter test test/extensions/snapshot_ext_test.dart test/extensions/screenshot_suppression_test.dart test/extensions/screenshot_ext_test.dart`
Expected: PASS (existing screenshot test still green).

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_probe/lib/src/extensions/snapshot_ext.dart packages/agent_wires_probe/lib/src/extensions/screenshot_ext.dart packages/agent_wires_probe/test/extensions/snapshot_ext_test.dart packages/agent_wires_probe/test/extensions/screenshot_suppression_test.dart
git commit -m "feat(probe): snapshot/screenshot flash + capture suppression"
```

---

## Task 13: label_element triggers a point-at highlight (MCP)

**Files:**
- Modify: `packages/agent_wires_mcp/lib/src/tools/memory_tools.dart`
- Test: `packages/agent_wires_mcp/test/tools/memory_tools_overlay_test.dart`

This reuses `inspect`'s highlight: when `label_element` resolves an `element_id`, it best-effort calls `ext.qa.inspect` so the named element flashes for a watcher. Fingerprint-only labels (no live element) are not highlighted.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:agent_wires_mcp/src/map/semantic_map.dart';
import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/tools/memory_tools.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  test('label_element with element_id calls ext.qa.inspect to highlight',
      () async {
    final vm = _RecordingVm();
    final session = AppSession.attached(vm);
    final map = SemanticMap.inMemory();
    final tools = memoryTools(map, session: session);
    final label = tools.firstWhere((t) => t.name == 'label_element');

    await label.handler({'element_id': 'e_3', 'name': 'Submit'});

    expect(vm.calls.where((c) => c.$1 == 'ext.qa.inspect'), isNotEmpty);
    final inspectCall =
        vm.calls.firstWhere((c) => c.$1 == 'ext.qa.inspect');
    expect(inspectCall.$2?['element_id'], 'e_3');
  });
}

class _RecordingVm implements VmClient {
  final List<(String, Map<String, String>?)> calls = [];

  @override
  Future<Map<String, dynamic>> callExtension(String name,
      [Map<String, String>? params]) async {
    calls.add((name, params));
    if (name == 'ext.qa.snapshot') {
      return {
        'elements': [
          {'id': 'e_3', 'fingerprint': 'fp_e3'},
        ],
      };
    }
    return {'ok': true};
  }

  @override
  // ignore: avoid_annotating_with_dynamic
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
```

Note: verify `SemanticMap.inMemory()` and `AppSession.attached(...)` exist with these signatures by reading `semantic_map.dart` and `app_session.dart`; if the in-memory constructor differs, use the same construction the existing `memory_tools_test.dart` uses (read it first and mirror it). Verify `VmClient.callExtension`'s real signature and match the override exactly.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/agent_wires_mcp && dart test test/tools/memory_tools_overlay_test.dart`
Expected: FAIL — no `ext.qa.inspect` call recorded.

- [ ] **Step 3: Write minimal implementation**

In `memory_tools.dart`, inside the `label_element` handler, immediately after the block that finds `match` and assigns `fp` (i.e. right after the `if (fp == null) { ... }` validation that follows `fp = match['fingerprint'] ...`), add a best-effort highlight call. It must use `elementId` and `vm`, both already in scope in that branch:

```dart
            // Best-effort: flash a point-at highlight on the element being
            // named, so a human watching sees what got labelled. Reuses
            // inspect's overlay highlight; ignore any failure.
            try {
              await vm.callExtension(
                  'ext.qa.inspect', {'element_id': elementId, 'include_descendants': 'false'});
            } catch (_) {}
```

Place it just before `final existing = map.get(fp);`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/agent_wires_mcp && dart test test/tools/memory_tools_overlay_test.dart`
Expected: PASS.

Also confirm the existing memory tools test still passes:
Run: `cd packages/agent_wires_mcp && dart test test/tools/memory_tools_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_mcp/lib/src/tools/memory_tools.dart packages/agent_wires_mcp/test/tools/memory_tools_overlay_test.dart
git commit -m "feat(mcp): label_element flashes a point-at highlight"
```

---

## Task 14: MCP set_action_overlay tool

**Files:**
- Create: `packages/agent_wires_mcp/lib/src/tools/overlay_tools.dart`
- Modify: `packages/agent_wires_mcp/bin/agent_wires_mcp.dart`
- Test: `packages/agent_wires_mcp/test/tools/overlay_tools_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/tools/overlay_tools.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

AppSession _session() => AppSession.attached(_FakeVm());

void main() {
  test('overlayTools exposes set_action_overlay requiring enabled', () {
    final tools = overlayTools(_session());
    expect(tools.map((t) => t.name).toList(), ['set_action_overlay']);
    final t = tools.single;
    expect((t.inputSchema['required'] as List), contains('enabled'));
    expect((t.inputSchema['properties'] as Map), contains('enabled'));
  });
}

class _FakeVm implements VmClient {
  @override
  // ignore: avoid_annotating_with_dynamic
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/agent_wires_mcp && dart test test/tools/overlay_tools_test.dart`
Expected: FAIL — `overlay_tools.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `overlay_tools.dart`:

```dart
import 'dart:convert';
import '../mcp/tool.dart';
import '../session/app_session.dart';

List<Tool> overlayTools(AppSession session) => [
      Tool(
        name: 'set_action_overlay',
        description:
            'Toggles the on-screen action overlay — the ripples, highlight '
            'boxes and flashes the probe draws where you tap, type, point, and '
            'look. It is a visual aid for a human watching the device and '
            'never appears in your `screenshot` or `snapshot`. On by default. '
            'Pass `enabled:false` to turn it off (e.g. for a clean screen '
            'recording) and `true` to turn it back on.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'enabled': {'type': 'boolean'},
          },
          'required': ['enabled'],
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.set_overlay', {
            'enabled': (args['enabled'] == true).toString(),
          });
          return _result(jsonEncode(json));
        },
      ),
    ];

Map<String, dynamic> _result(String text) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
    };
```

In `bin/agent_wires_mcp.dart`, add the import near the other tool imports (match the existing import style/paths):

```dart
import 'package:agent_wires_mcp/src/tools/overlay_tools.dart';
```

(If the bin imports tools via relative paths, mirror that. Read the import block at the top of the file first.)

Then register the tool in the `McpProtocol(tools: [...])` list, after `...actionTools(session),`:

```dart
    ...actionTools(session),
    ...overlayTools(session),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/agent_wires_mcp && dart test test/tools/overlay_tools_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/agent_wires_mcp/lib/src/tools/overlay_tools.dart packages/agent_wires_mcp/bin/agent_wires_mcp.dart packages/agent_wires_mcp/test/tools/overlay_tools_test.dart
git commit -m "feat(mcp): set_action_overlay tool"
```

---

## Task 15: Version bumps, changelogs, README, full gate

**Files:**
- Modify: `packages/agent_wires_probe/pubspec.yaml`, `packages/agent_wires_probe/lib/src/version.dart`, `packages/agent_wires_probe/CHANGELOG.md`, `packages/agent_wires_probe/README.md`
- Modify: `packages/agent_wires_mcp/pubspec.yaml`, `packages/agent_wires_mcp/lib/src/version.dart`, `packages/agent_wires_mcp/CHANGELOG.md`, `packages/agent_wires_mcp/README.md`

- [ ] **Step 1: Bump the probe version (test-first via the existing pin)**

The probe's `test/version_test.dart` already asserts `probeVersion == pubspec version`. Bump both so it stays green.

In `packages/agent_wires_probe/pubspec.yaml`, change `version: 0.1.6` → `version: 0.1.7`.
In `packages/agent_wires_probe/lib/src/version.dart`, change `'0.1.6'` → `'0.1.7'`.

Run: `cd packages/agent_wires_probe && flutter test test/version_test.dart`
Expected: PASS.

- [ ] **Step 2: Bump the mcp version**

In `packages/agent_wires_mcp/pubspec.yaml`, bump `version:` `0.1.5` → `0.1.6`.
In `packages/agent_wires_mcp/lib/src/version.dart`:
- `packageVersion` `'0.1.5'` → `'0.1.6'`
- `recommendedProbeVersion` `'0.1.6'` → `'0.1.7'`

- [ ] **Step 3: Probe CHANGELOG**

Prepend to `packages/agent_wires_probe/CHANGELOG.md`:

```markdown
## 0.1.7

Adds an on-screen **action overlay** — a narration layer for a human watching
the agent drive the app. Debug-only (like the rest of the probe) and on by
default; it never appears in the agent's `screenshot` or `snapshot`.

- Draws a ripple where the agent taps/long-presses, a trail for swipes/scrolls
  and back, a highlight box (with caption) for `enter_text`/`clear_text` and
  `inspect`/point-at, and a brief border flash + badge for `screenshot` and
  `snapshot`.
- Rendered via a single `IgnorePointer` overlay inserted into the app's topmost
  `Overlay`; effects auto-expire and are capped so a burst can't accumulate.
- Kept out of the agent's perception: the snapshot walker skips the overlay
  subtree, and the screenshot path suppresses the overlay for the captured
  frame.
- Toggle at runtime with the new `ext.qa.set_overlay` extension (paired with the
  MCP `set_action_overlay` tool); compile-time opt-out via
  `AgentWiresProbe.install(actionOverlay: false)`.
```

- [ ] **Step 4: MCP CHANGELOG**

Prepend to `packages/agent_wires_mcp/CHANGELOG.md`:

```markdown
## 0.1.6

Adds the **action overlay** narration layer (pairs with `agent_wires_probe`
0.1.7). **Tool count grows 24 → 25.**

- New `set_action_overlay(enabled)` tool toggles the probe's on-screen overlay
  — the ripples/highlights/flashes drawn where the agent taps, types, points,
  and looks. It is for a human watching the device and never appears in
  `screenshot`/`snapshot`. On by default.
- `label_element` now flashes a point-at highlight on the named element (via the
  probe) so a watcher sees what was labelled.
- `recommendedProbeVersion` tracks `agent_wires_probe` 0.1.7.
```

- [ ] **Step 5: READMEs**

In both `packages/agent_wires_mcp/README.md` and `packages/agent_wires_probe/README.md`:
- Update the tool count `24` → `25` wherever it appears.
- Add `set_action_overlay` to the tool listing/table next to the other tools.
- Add a short "Action overlay" subsection: on by default, debug-only, for a human watching, never in `screenshot`/`snapshot`, toggle with `set_action_overlay`, compile-time opt-out via `AgentWiresProbe.install(actionOverlay: false)`.
- Bump any dependency pin examples: probe `^0.1.6` → `^0.1.7`.

(Read each README first and edit the exact lines; do not invent counts — grep for `24` to find them: `grep -n "24" packages/*/README.md`.)

- [ ] **Step 6: Full gate — analyze + all tests, both packages**

```bash
cd packages/agent_wires_probe && flutter analyze && flutter test
cd ../agent_wires_mcp && dart analyze && dart test
```
Expected: no analyzer issues; all tests pass.

- [ ] **Step 7: Commit**

```bash
git add packages/agent_wires_probe/pubspec.yaml packages/agent_wires_probe/lib/src/version.dart packages/agent_wires_probe/CHANGELOG.md packages/agent_wires_probe/README.md packages/agent_wires_mcp/pubspec.yaml packages/agent_wires_mcp/lib/src/version.dart packages/agent_wires_mcp/CHANGELOG.md packages/agent_wires_mcp/README.md
git commit -m "release: action overlay — probe 0.1.7, mcp 0.1.6"
```

---

## Self-Review

**Spec coverage:**
- Audience = human-live, not in screenshots → Tasks 11 (snapshot skip) + 12 (screenshot suppression). ✓
- Events: touch (Tasks 7, 8), text (9), inspect/point-at (10) + label_element (13), screenshot/snapshot (12). ✓
- On-by-default + runtime toggle → Tasks 5, 6, 14. ✓
- Compile-time opt-out → Task 6. ✓
- Components: controller (2), effect model (1), host/painter/marker (3), installer (4). ✓
- Effect visuals (ripple/trail/highlight/flash, color-coded, capped) → Tasks 1–3. ✓
- Versions/changelog/README/tool-count 25 → Task 15. ✓

**Type consistency:** `ActionOverlayController` API (`showTap/showDrag/showHighlight/showFlash`, `setEnabled`, `begin/endCaptureSuppression`, `removeEffect`, `effects`/`visibleEffects`, `maxEffects`, `reset`) is defined in Task 2 and used identically in Tasks 3, 5–13. `OverlayFlashKind.{screenshot,snapshot}` from Task 1 used in 12. `ActionOverlayInstaller.{ensureInstalled,reset}` from Task 4 used in 7–13. `AgentWiresOverlayMarker` from Task 3 used in 11. `captureWithOverlaySuppressed` defined+used in Task 12. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. Tasks that extend existing test files instruct reading them first to match harnesses (necessary because those harnesses vary) but still give the exact new test code and assertions. ✓

**Known integration risks flagged inline:** global-singleton test hygiene (tearDown reset + pumpAndSettle) is called out at the top and repeated per wiring task; `VmClient.callExtension`/`AppSession.attached`/`SemanticMap.inMemory` signatures are flagged for verification against the real files in Tasks 13–14.
