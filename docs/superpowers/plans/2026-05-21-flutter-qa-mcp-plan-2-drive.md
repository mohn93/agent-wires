# Flutter QA MCP — Plan 2: Drive (Action + Sync Tools) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Flutter QA MCP foundation so an LLM agent can not only *see* the running Flutter app (Plan 1) but also *drive* it — tapping, scrolling, typing, navigating, and waiting for state to settle.

**Architecture:** Same two-process model as Plan 1. The probe gains 10 new VM service extensions (7 action, 3 sync). The MCP server gains two new tool factory files exposing them. Element IDs from a recent `snapshot` resolve to live `Element` instances via a centralized resolver (refactored out of the existing `inspect` extension). Actions return `{success, error?}` payloads; the agent is expected to call `snapshot` afterwards when it needs the resulting state.

**Tech Stack (no new deps):**
- Dart 3.5+ / Flutter 3.24+
- `package:flutter/gestures.dart` (PointerEvent synthesis through `GestureBinding`)
- `package:flutter/services.dart` (`TextInput`)
- `package:flutter/scheduler.dart` (`SchedulerBinding` for idle detection)
- Existing Plan 1 infrastructure: walker, classifier, snapshot builder, MCP protocol/transport

**What changes in the repo (additions only — no Plan 1 file replaced):**

```
packages/flutter_qa_probe/lib/src/
├── resolver/
│   └── element_resolver.dart       (NEW — centralizes element_id → Element lookup)
├── actions/
│   ├── gesture_synth.dart          (NEW — PointerEvent helper)
│   ├── text_input_driver.dart      (NEW — TextInput wrapper)
│   └── scroll_driver.dart          (NEW — Scrollable detection + drive)
├── sync/
│   ├── idle_predicate.dart         (NEW — frames + animations + HTTP idleness)
│   └── http_inflight_tracker.dart  (NEW — HttpOverrides-based in-flight counter)
└── extensions/
    ├── tap_ext.dart                (NEW)
    ├── long_press_ext.dart         (NEW)
    ├── swipe_ext.dart              (NEW)
    ├── enter_text_ext.dart         (NEW)
    ├── clear_text_ext.dart         (NEW)
    ├── scroll_ext.dart             (NEW)
    ├── press_back_ext.dart         (NEW)
    ├── wait_for_idle_ext.dart      (NEW)
    ├── wait_for_route_ext.dart     (NEW)
    └── wait_for_element_ext.dart   (NEW)

packages/flutter_qa_mcp/lib/src/tools/
├── action_tools.dart               (NEW — 7 action tools)
└── sync_tools.dart                 (NEW — 3 sync tools)
```

**Out of scope (deferred to Plan 3 or later):**
- Persistent semantic map / label storage
- VLM proposals
- Web dashboard
- Network mocking
- Multi-touch gestures (pinch, multi-finger)
- Action burst caching (re-walks per action are acceptable for v1)

---

## Task 1: Centralize element_id resolver

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/resolver/element_resolver.dart`
- Modify: `packages/flutter_qa_probe/lib/src/extensions/inspect_ext.dart`
- Create: `packages/flutter_qa_probe/test/resolver/element_resolver_test.dart`

**Context:** Today `inspect_ext.dart` re-walks the tree, filters by `promote + bounds != null`, then indexes by parsing `e_${N}`. Plan 2 needs the same lookup from 10 new extensions. Extract once.

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/resolver/element_resolver_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/resolver/element_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resolves e_0 to the first promoted+bounded element', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ElevatedButton(onPressed: () {}, child: const Text('Go'))),
    ));
    final result = ElementResolver.resolve('e_0');
    expect(result, isNotNull);
    expect(result!.widget.runtimeType.toString(), 'ElevatedButton');
  });

  testWidgets('returns null for an out-of-range id', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    expect(ElementResolver.resolve('e_999'), isNull);
  });

  test('returns null for malformed id', () {
    expect(ElementResolver.resolve('not_an_id'), isNull);
    expect(ElementResolver.resolve(''), isNull);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/resolver/element_resolver.dart
import 'package:flutter/widgets.dart';
import '../tree/classifier.dart';
import '../tree/walker.dart';

class ElementResolver {
  /// Walks the live tree in the same order as `SnapshotBuilder.build()` and
  /// returns the Element corresponding to `elementId` (e.g. "e_3"), or null
  /// if the id is malformed or out of range.
  static Element? resolve(String elementId) {
    if (!elementId.startsWith('e_')) return null;
    final idx = int.tryParse(elementId.substring(2));
    if (idx == null || idx < 0) return null;

    final raw = ElementTreeWalker.walkFromRoot();
    var cursor = 0;
    for (final node in raw) {
      final cls = Classifier.classify(node.element.widget);
      if (cls != Classification.promote) continue;
      if (node.bounds == null) continue;
      if (cursor == idx) return node.element;
      cursor++;
    }
    return null;
  }
}
```

- [ ] **Step 3: Refactor inspect extension to use resolver**

Replace the manual walk-and-index logic in `packages/flutter_qa_probe/lib/src/extensions/inspect_ext.dart` with `ElementResolver.resolve(id)`. The error message stays the same ("element not found"). The rest of the function (DiagnosticPropertiesBuilder, ancestors, JSON response) is unchanged.

```dart
// in handle(), replace the walk+filter+idx block with:
final id = params['element_id'];
if (id == null || id.isEmpty) {
  return developer.ServiceExtensionResponse.error(
    developer.ServiceExtensionResponse.invalidParams,
    jsonEncode({'error': 'element_id required'}),
  );
}
final element = ElementResolver.resolve(id);
if (element == null) {
  return developer.ServiceExtensionResponse.error(
    developer.ServiceExtensionResponse.extensionError,
    jsonEncode({'error': 'element not found'}),
  );
}
// then use `element` instead of `node.element`. For widget_type use element.widget.runtimeType.toString().
// For creation_location: keep what inspect already shows — call ElementTreeWalker.walkFromRoot()'s creationLocation
// for this element. Easiest: just omit creation_location from inspect's response, or grep it from RawNode by element identity.
```

Simpler choice: have `ElementResolver.resolve` return a richer object that also yields the `creationLocation` it computed. Defer that to Plan 3 cleanup; for now, inspect can drop `creation_location` from its response (it's available via `snapshot`).

- [ ] **Step 4: Run tests + analyze**

```bash
cd packages/flutter_qa_probe && flutter test && flutter analyze
```
All existing tests + 3 new tests pass. Analyze clean.

- [ ] **Step 5: Commit**

```
git add packages/flutter_qa_probe/
git commit -m "refactor(probe): centralize element_id → Element resolution"
```

---

## Task 2: PointerEvent synthesizer utility

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/actions/gesture_synth.dart`
- Create: `packages/flutter_qa_probe/test/actions/gesture_synth_test.dart`

**Context:** Tap, long-press, and swipe all dispatch raw `PointerEvent`s through `GestureBinding.instance.handlePointerEvent`. Centralize the math: given a `Rect`, compute the center point in global coords; build a Pointer down/up sequence with monotonic timestamps and a stable `pointer` id. This is the only place `PointerEvent` construction lives.

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/actions/gesture_synth_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/actions/gesture_synth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapAt triggers onTap on a Button at given coords', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => tapped++,
            child: const Text('Hit'),
          ),
        ),
      ),
    ));

    final ro = tester.renderObject(find.byType(ElevatedButton));
    final box = ro as RenderBox;
    final center = box.localToGlobal(box.size.center(Offset.zero));

    await GestureSynth.tapAt(center);
    await tester.pumpAndSettle();

    expect(tapped, 1);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/actions/gesture_synth.dart
import 'package:flutter/gestures.dart';

class GestureSynth {
  static int _nextPointer = 1;

  static Future<void> tapAt(Offset position) async {
    final pointer = _nextPointer++;
    final binding = GestureBinding.instance;
    final ts = Duration.zero;
    binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      position: position,
      timeStamp: ts,
    ));
    binding.handlePointerEvent(PointerUpEvent(
      pointer: pointer,
      position: position,
      timeStamp: ts + const Duration(milliseconds: 50),
    ));
  }

  static Future<void> longPressAt(Offset position, {Duration hold = const Duration(milliseconds: 600)}) async {
    final pointer = _nextPointer++;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      position: position,
      timeStamp: Duration.zero,
    ));
    await Future<void>.delayed(hold);
    binding.handlePointerEvent(PointerUpEvent(
      pointer: pointer,
      position: position,
      timeStamp: hold + const Duration(milliseconds: 50),
    ));
  }

  static Future<void> swipe(Offset from, Offset to, {Duration duration = const Duration(milliseconds: 300), int steps = 20}) async {
    final pointer = _nextPointer++;
    final binding = GestureBinding.instance;
    final dt = duration ~/ steps;
    binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      position: from,
      timeStamp: Duration.zero,
    ));
    var t = dt;
    for (var i = 1; i <= steps; i++) {
      final frac = i / steps;
      final pos = Offset.lerp(from, to, frac)!;
      binding.handlePointerEvent(PointerMoveEvent(
        pointer: pointer,
        position: pos,
        timeStamp: t,
      ));
      t += dt;
    }
    binding.handlePointerEvent(PointerUpEvent(
      pointer: pointer,
      position: to,
      timeStamp: t,
    ));
  }
}
```

- [ ] **Step 3: Run test + analyze**

```bash
cd packages/flutter_qa_probe && flutter test test/actions/gesture_synth_test.dart && flutter analyze
```

- [ ] **Step 4: Commit**

```
git add packages/flutter_qa_probe/
git commit -m "feat(probe): PointerEvent synthesizer for tap/long-press/swipe"
```

---

## Task 3: `ext.qa.tap` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/tap_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart` (register extension)
- Create: `packages/flutter_qa_probe/test/extensions/tap_ext_test.dart`

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/extensions/tap_ext_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/tap_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tap on e_0 triggers the button onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () => taps++, child: const Text('Press')),
      ),
    ));

    final resp = await TapExtension.handle('ext.qa.tap', {'element_id': 'e_0'});
    await tester.pumpAndSettle();

    expect(resp.isError, isFalse);
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(taps, 1);
  });

  testWidgets('tap on missing id returns error response with success:false', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    final resp = await TapExtension.handle('ext.qa.tap', {'element_id': 'e_999'});
    expect(resp.isError, isFalse); // extension responds OK; tool reports failure in body
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
    expect(body['error'], contains('not found'));
  });
}
```

Note the convention: action extensions always return a JSON body with `success: bool` and optional `error`. The HTTP-style "isError" path is reserved for unexpected runtime exceptions; missing-id is a normal action outcome.

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/extensions/tap_ext.dart
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/rendering.dart';
import '../actions/gesture_synth.dart';
import '../resolver/element_resolver.dart';

class TapExtension {
  static const String name = 'ext.qa.tap';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final id = params['element_id'];
    if (id == null || id.isEmpty) {
      return _ok({'success': false, 'error': 'element_id required'});
    }
    final element = ElementResolver.resolve(id);
    if (element == null) {
      return _ok({'success': false, 'error': 'element not found: $id'});
    }
    final ro = element.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) {
      return _ok({'success': false, 'error': 'element has no render box'});
    }
    final center = ro.localToGlobal(ro.size.center(Offset.zero));
    try {
      await GestureSynth.tapAt(center);
      return _ok({'success': true, 'at': {'x': center.dx, 'y': center.dy}});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
```

- [ ] **Step 3: Register in probe**

In `packages/flutter_qa_probe/lib/src/probe.dart`, import `tap_ext.dart` and add to `install()`:

```dart
_register(TapExtension.name, TapExtension.handle);
```

- [ ] **Step 4: Tests + analyze**

```bash
cd packages/flutter_qa_probe && flutter test && flutter analyze
```

- [ ] **Step 5: Commit**

```
git add packages/flutter_qa_probe/
git commit -m "feat(probe): ext.qa.tap extension"
```

---

## Task 4: `ext.qa.long_press` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/long_press_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/extensions/long_press_ext_test.dart`

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/extensions/long_press_ext_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/long_press_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long_press on a GestureDetector triggers onLongPress', (tester) async {
    var longPresses = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          onLongPress: () => longPresses++,
          child: const SizedBox(width: 100, height: 100, child: ColoredBox(color: Color(0xFF000000))),
        ),
      ),
    ));

    final resp = await LongPressExtension.handle('ext.qa.long_press', {
      'element_id': 'e_0',
      'duration_ms': '600',
    });
    await tester.pumpAndSettle();

    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(longPresses, 1);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/extensions/long_press_ext.dart
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/rendering.dart';
import '../actions/gesture_synth.dart';
import '../resolver/element_resolver.dart';

class LongPressExtension {
  static const String name = 'ext.qa.long_press';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final id = params['element_id'];
    if (id == null || id.isEmpty) {
      return _ok({'success': false, 'error': 'element_id required'});
    }
    final element = ElementResolver.resolve(id);
    if (element == null) {
      return _ok({'success': false, 'error': 'element not found: $id'});
    }
    final ro = element.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) {
      return _ok({'success': false, 'error': 'element has no render box'});
    }
    final ms = int.tryParse(params['duration_ms'] ?? '600') ?? 600;
    final center = ro.localToGlobal(ro.size.center(Offset.zero));
    try {
      await GestureSynth.longPressAt(center, hold: Duration(milliseconds: ms));
      return _ok({'success': true});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
```

- [ ] **Step 3: Register** in `probe.dart`.

- [ ] **Step 4: Tests + analyze.**

- [ ] **Step 5: Commit** with message `feat(probe): ext.qa.long_press extension`.

---

## Task 5: `ext.qa.swipe` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/swipe_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/extensions/swipe_ext_test.dart`

**Context:** Unlike tap/long-press, swipe takes absolute coordinates rather than an element_id — the agent already knows where things are from `snapshot.bounds`, and many swipe targets (carousels, dismissible cards) aren't easily addressed by their bounding box.

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/extensions/swipe_ext_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/swipe_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('swipe moves a horizontal scroll position', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          itemCount: 50,
          itemBuilder: (_, i) => SizedBox(width: 100, height: 100, child: Text('$i')),
        ),
      ),
    ));

    expect(controller.position.pixels, 0);

    final resp = await SwipeExtension.handle('ext.qa.swipe', {
      'from_x': '300',
      'from_y': '50',
      'to_x': '50',
      'to_y': '50',
    });
    await tester.pumpAndSettle();

    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(controller.position.pixels, greaterThan(0));
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/extensions/swipe_ext.dart
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/rendering.dart';
import '../actions/gesture_synth.dart';

class SwipeExtension {
  static const String name = 'ext.qa.swipe';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final fromX = double.tryParse(params['from_x'] ?? '');
    final fromY = double.tryParse(params['from_y'] ?? '');
    final toX = double.tryParse(params['to_x'] ?? '');
    final toY = double.tryParse(params['to_y'] ?? '');
    if (fromX == null || fromY == null || toX == null || toY == null) {
      return _ok({'success': false, 'error': 'from_x, from_y, to_x, to_y required'});
    }
    final ms = int.tryParse(params['duration_ms'] ?? '300') ?? 300;
    try {
      await GestureSynth.swipe(
        Offset(fromX, fromY),
        Offset(toX, toY),
        duration: Duration(milliseconds: ms),
      );
      return _ok({'success': true});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
```

- [ ] **Step 3: Register, test, commit** with message `feat(probe): ext.qa.swipe extension`.

---

## Task 6: TextInput driver utility

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/actions/text_input_driver.dart`
- Create: `packages/flutter_qa_probe/test/actions/text_input_driver_test.dart`

**Context:** `enter_text` and `clear_text` both need to (a) focus the `TextField`, (b) replace its current `EditableTextState` value via `TextInput`. Extract the mechanics.

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/actions/text_input_driver_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/actions/text_input_driver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('setText replaces the contents of a focused TextField', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(controller: controller)),
    ));

    final field = tester.element(find.byType(TextField));
    await TextInputDriver.setText(field, 'hello world');
    await tester.pumpAndSettle();

    expect(controller.text, 'hello world');
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/actions/text_input_driver.dart
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class TextInputDriver {
  /// Sets the text on a `TextField` / `EditableText` rooted at `element`.
  /// Throws if no `EditableTextState` is found in the subtree.
  static Future<void> setText(Element element, String value) async {
    final editable = _findEditableTextState(element);
    if (editable == null) {
      throw StateError('no EditableTextState in subtree of ${element.widget.runtimeType}');
    }
    editable.userUpdateTextEditingValue(
      TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      ),
      SelectionChangedCause.keyboard,
    );
  }

  static EditableTextState? _findEditableTextState(Element root) {
    EditableTextState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        found = e.state as EditableTextState;
        return;
      }
      e.visitChildren(visit);
    }
    visit(root);
    return found;
  }
}
```

- [ ] **Step 3: Test, analyze, commit** with message `feat(probe): TextInput driver utility`.

---

## Task 7: `ext.qa.enter_text` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/enter_text_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/extensions/enter_text_ext_test.dart`

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/extensions/enter_text_ext_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/enter_text_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('enter_text fills a TextField identified by element_id', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(controller: controller)),
    ));

    final resp = await EnterTextExtension.handle('ext.qa.enter_text', {
      'element_id': 'e_0',
      'text': 'hello',
    });
    await tester.pumpAndSettle();

    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(controller.text, 'hello');
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/extensions/enter_text_ext.dart
import 'dart:convert';
import 'dart:developer' as developer;
import '../actions/text_input_driver.dart';
import '../resolver/element_resolver.dart';

class EnterTextExtension {
  static const String name = 'ext.qa.enter_text';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final id = params['element_id'];
    final text = params['text'];
    if (id == null || id.isEmpty) {
      return _ok({'success': false, 'error': 'element_id required'});
    }
    if (text == null) {
      return _ok({'success': false, 'error': 'text required'});
    }
    final element = ElementResolver.resolve(id);
    if (element == null) {
      return _ok({'success': false, 'error': 'element not found: $id'});
    }
    try {
      await TextInputDriver.setText(element, text);
      return _ok({'success': true});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
```

- [ ] **Step 3: Register, test, commit** with message `feat(probe): ext.qa.enter_text extension`.

---

## Task 8: `ext.qa.clear_text` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/clear_text_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/extensions/clear_text_ext_test.dart`

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/extensions/clear_text_ext_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/clear_text_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clear_text empties a populated TextField', (tester) async {
    final controller = TextEditingController(text: 'pre-existing');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(controller: controller)),
    ));

    final resp = await ClearTextExtension.handle('ext.qa.clear_text', {
      'element_id': 'e_0',
    });
    await tester.pumpAndSettle();

    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(controller.text, '');
  });
}
```

- [ ] **Step 2: Implement** — same shape as `EnterTextExtension` but always sets text to `''`. Use the same `TextInputDriver.setText(element, '')` call.

```dart
// packages/flutter_qa_probe/lib/src/extensions/clear_text_ext.dart
import 'dart:convert';
import 'dart:developer' as developer;
import '../actions/text_input_driver.dart';
import '../resolver/element_resolver.dart';

class ClearTextExtension {
  static const String name = 'ext.qa.clear_text';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final id = params['element_id'];
    if (id == null || id.isEmpty) {
      return _ok({'success': false, 'error': 'element_id required'});
    }
    final element = ElementResolver.resolve(id);
    if (element == null) {
      return _ok({'success': false, 'error': 'element not found: $id'});
    }
    try {
      await TextInputDriver.setText(element, '');
      return _ok({'success': true});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
```

- [ ] **Step 3: Register, test, commit** with message `feat(probe): ext.qa.clear_text extension`.

---

## Task 9: Scroll driver utility + `ext.qa.scroll` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/actions/scroll_driver.dart`
- Create: `packages/flutter_qa_probe/lib/src/extensions/scroll_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/extensions/scroll_ext_test.dart`

**Context:** Scroll has two modes: with an `element_id` (drive that specific Scrollable) or without (drive the nearest visible Scrollable to the screen center). Both reduce to: locate a `ScrollableState`, call `position.animateTo`.

- [ ] **Step 1: ScrollDriver**

```dart
// packages/flutter_qa_probe/lib/src/actions/scroll_driver.dart
import 'package:flutter/widgets.dart';

enum ScrollDirection { up, down, left, right }

class ScrollDriver {
  static Future<bool> scrollIn(Element root, ScrollDirection direction, double pixels) async {
    final scrollable = _firstDescendantScrollable(root);
    if (scrollable == null) return false;
    return _drive(scrollable, direction, pixels);
  }

  static Future<bool> scrollAnyVisible(ScrollDirection direction, double pixels) async {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return false;
    final scrollable = _firstDescendantScrollable(root);
    if (scrollable == null) return false;
    return _drive(scrollable, direction, pixels);
  }

  static Future<bool> _drive(ScrollableState state, ScrollDirection direction, double pixels) async {
    final position = state.position;
    final isVertical = state.axisDirection == AxisDirection.down ||
        state.axisDirection == AxisDirection.up;
    final delta = switch (direction) {
      ScrollDirection.up => -pixels,
      ScrollDirection.down => pixels,
      ScrollDirection.left => -pixels,
      ScrollDirection.right => pixels,
    };
    if (isVertical &&
        (direction == ScrollDirection.left || direction == ScrollDirection.right)) {
      return false;
    }
    if (!isVertical &&
        (direction == ScrollDirection.up || direction == ScrollDirection.down)) {
      return false;
    }
    await position.animateTo(
      (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    return true;
  }

  static ScrollableState? _firstDescendantScrollable(Element root) {
    ScrollableState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is ScrollableState) {
        found = e.state as ScrollableState;
        return;
      }
      e.visitChildren(visit);
    }
    if (root is StatefulElement && root.state is ScrollableState) {
      return root.state as ScrollableState;
    }
    visit(root);
    return found;
  }
}
```

- [ ] **Step 2: Failing test**

```dart
// packages/flutter_qa_probe/test/extensions/scroll_ext_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/scroll_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scroll down moves the ScrollPosition', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
        ),
      ),
    ));

    final resp = await ScrollExtension.handle('ext.qa.scroll', {
      'direction': 'down',
      'distance': '200',
    });
    await tester.pumpAndSettle();

    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(controller.position.pixels, greaterThan(0));
  });
}
```

- [ ] **Step 3: Implement extension**

```dart
// packages/flutter_qa_probe/lib/src/extensions/scroll_ext.dart
import 'dart:convert';
import 'dart:developer' as developer;
import '../actions/scroll_driver.dart';
import '../resolver/element_resolver.dart';

class ScrollExtension {
  static const String name = 'ext.qa.scroll';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final dirStr = (params['direction'] ?? '').toLowerCase();
    final direction = switch (dirStr) {
      'up' => ScrollDirection.up,
      'down' => ScrollDirection.down,
      'left' => ScrollDirection.left,
      'right' => ScrollDirection.right,
      _ => null,
    };
    if (direction == null) {
      return _ok({'success': false, 'error': 'direction must be up|down|left|right'});
    }
    final distance = double.tryParse(params['distance'] ?? '200') ?? 200;
    final id = params['element_id'];
    try {
      bool ok;
      if (id != null && id.isNotEmpty) {
        final element = ElementResolver.resolve(id);
        if (element == null) {
          return _ok({'success': false, 'error': 'element not found: $id'});
        }
        ok = await ScrollDriver.scrollIn(element, direction, distance);
      } else {
        ok = await ScrollDriver.scrollAnyVisible(direction, distance);
      }
      if (!ok) {
        return _ok({'success': false, 'error': 'no scrollable found or axis mismatch'});
      }
      return _ok({'success': true});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
```

- [ ] **Step 4: Register, test, analyze, commit** with message `feat(probe): ext.qa.scroll extension`.

---

## Task 10: `ext.qa.press_back` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/press_back_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/extensions/press_back_ext_test.dart`

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/extensions/press_back_ext_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/press_back_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('press_back pops the top route', (tester) async {
    await tester.pumpWidget(MaterialApp(
      initialRoute: '/',
      routes: {
        '/': (_) => const Scaffold(body: Text('home')),
        '/next': (_) => const Scaffold(body: Text('next')),
      },
    ));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/next');
    await tester.pumpAndSettle();
    expect(find.text('next'), findsOneWidget);

    final resp = await PressBackExtension.handle('ext.qa.press_back', const {});
    await tester.pumpAndSettle();
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(find.text('home'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/extensions/press_back_ext.dart
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/widgets.dart';

class PressBackExtension {
  static const String name = 'ext.qa.press_back';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final root = WidgetsBinding.instance.rootElement;
      if (root == null) {
        return _ok({'success': false, 'error': 'no root element'});
      }
      NavigatorState? nav;
      void visit(Element e) {
        if (nav != null) return;
        if (e is StatefulElement && e.state is NavigatorState) {
          nav = e.state as NavigatorState;
          return;
        }
        e.visitChildren(visit);
      }
      visit(root);
      if (nav == null) {
        return _ok({'success': false, 'error': 'no Navigator found'});
      }
      final popped = await nav!.maybePop();
      return _ok({'success': popped});
    } catch (e) {
      return _ok({'success': false, 'error': e.toString()});
    }
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
```

- [ ] **Step 3: Register, test, commit** with message `feat(probe): ext.qa.press_back extension`.

---

## Task 11: HTTP in-flight tracker

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/sync/http_inflight_tracker.dart`
- Create: `packages/flutter_qa_probe/test/sync/http_inflight_tracker_test.dart`

**Context:** `wait_for_idle` needs to know when HTTP traffic has settled. We install an `HttpOverrides` wrapper that increments a counter on `getUrl/post/etc.` and decrements when the response body is fully read. We do **not** modify the response; we just observe.

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/sync/http_inflight_tracker_test.dart
import 'dart:io';
import 'package:flutter_qa_probe/src/sync/http_inflight_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counter starts at 0 and tracks one inflight increment/decrement', () async {
    HttpInflightTracker.install();
    expect(HttpInflightTracker.inflight, 0);

    // Simulate a request lifecycle directly via the tracker's hooks.
    final token = HttpInflightTracker.beginRequest();
    expect(HttpInflightTracker.inflight, 1);
    HttpInflightTracker.endRequest(token);
    expect(HttpInflightTracker.inflight, 0);
  });

  test('install is idempotent', () {
    HttpInflightTracker.install();
    HttpInflightTracker.install();
    expect(HttpOverrides.current, isNotNull);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/sync/http_inflight_tracker.dart
import 'dart:io';

class HttpInflightTracker {
  static int _inflight = 0;
  static int _tokens = 0;
  static bool _installed = false;

  static int get inflight => _inflight;

  static void install() {
    if (_installed) return;
    _installed = true;
    HttpOverrides.global = _TrackingOverrides(HttpOverrides.current);
  }

  static int beginRequest() {
    _inflight++;
    return _tokens++;
  }

  static void endRequest(int token) {
    if (_inflight > 0) _inflight--;
  }
}

class _TrackingOverrides extends HttpOverrides {
  _TrackingOverrides(this.inner);
  final HttpOverrides? inner;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = inner?.createHttpClient(context) ?? super.createHttpClient(context);
    return _TrackingClient(client);
  }
}

class _TrackingClient implements HttpClient {
  _TrackingClient(this._inner);
  final HttpClient _inner;

  Future<HttpClientRequest> _track(Future<HttpClientRequest> Function() open) async {
    final token = HttpInflightTracker.beginRequest();
    try {
      final req = await open();
      // Decrement when the response is fully consumed.
      req.done.whenComplete(() => HttpInflightTracker.endRequest(token));
      return req;
    } catch (e) {
      HttpInflightTracker.endRequest(token);
      rethrow;
    }
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _track(() => _inner.getUrl(url));
  @override
  Future<HttpClientRequest> postUrl(Uri url) => _track(() => _inner.postUrl(url));
  @override
  Future<HttpClientRequest> putUrl(Uri url) => _track(() => _inner.putUrl(url));
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _track(() => _inner.deleteUrl(url));
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _track(() => _inner.patchUrl(url));
  @override
  Future<HttpClientRequest> headUrl(Uri url) => _track(() => _inner.headUrl(url));
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _track(() => _inner.openUrl(method, url));

  // Forward all other methods to the inner client.
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _track(() => _inner.get(host, port, path));
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _track(() => _inner.post(host, port, path));
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _track(() => _inner.put(host, port, path));
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _track(() => _inner.delete(host, port, path));
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _track(() => _inner.patch(host, port, path));
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _track(() => _inner.head(host, port, path));
  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) =>
      _track(() => _inner.open(method, host, port, path));

  // Setters/getters: pass through.
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool v) => _inner.autoUncompress = v;
  @override
  Duration get connectionTimeout => _inner.connectionTimeout ?? Duration.zero;
  @override
  set connectionTimeout(Duration? v) => _inner.connectionTimeout = v;
  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration v) => _inner.idleTimeout = v;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _inner.maxConnectionsPerHost = v;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? v) => _inner.userAgent = v;

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) =>
      _inner.addCredentials(url, realm, credentials);
  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) =>
      _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) =>
      _inner.authenticate = f;
  @override
  set authenticateProxy(Future<bool> Function(String host, int port, String scheme, String? realm)? f) =>
      _inner.authenticateProxy = f;
  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? cb) =>
      _inner.badCertificateCallback = cb;
  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri url, String? proxyHost, int? proxyPort)? f) =>
      _inner.connectionFactory = f;
  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
  @override
  set keyLog(Function(String line)? cb) => _inner.keyLog = cb;

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
```

Note: `HttpClient` has a large surface area. The forwarding above is comprehensive but tedious. If the analyzer complains about a missing override after a Flutter SDK bump, add it as a pass-through. **Do NOT delegate to `noSuchMethod`** — too easy to silently break.

- [ ] **Step 3: Test, analyze, commit** with message `feat(probe): HTTP in-flight request tracker via HttpOverrides`.

---

## Task 12: Idle predicate

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/sync/idle_predicate.dart`
- Create: `packages/flutter_qa_probe/test/sync/idle_predicate_test.dart`

**Context:** "Idle" means: no pending frames, no running animations, and no in-flight HTTP requests. The first two come from `SchedulerBinding.instance` directly; the third comes from `HttpInflightTracker`.

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/sync/idle_predicate_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/sync/idle_predicate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('isIdle returns true after pumpAndSettle on a static screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('static'))));
    await tester.pumpAndSettle();
    expect(IdlePredicate.isIdle(), isTrue);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/sync/idle_predicate.dart
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'http_inflight_tracker.dart';

class IdlePredicate {
  static bool isIdle() {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.hasScheduledFrame) return false;
    if (scheduler.transientCallbacks.isNotEmpty) return false; // animations
    if (HttpInflightTracker.inflight > 0) return false;
    return true;
  }

  /// Polls `isIdle` until it returns true OR `timeout` elapses.
  /// Returns whether idle was reached.
  static Future<bool> waitUntilIdle({
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 50),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (isIdle()) return true;
      await Future<void>.delayed(interval);
      WidgetsBinding.instance.scheduleFrame();
    }
    return isIdle();
  }
}
```

- [ ] **Step 3: Test, analyze, commit** with message `feat(probe): idle predicate combining frame/animation/HTTP state`.

---

## Task 13: `ext.qa.wait_for_idle` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/wait_for_idle_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart` (install `HttpInflightTracker` + register extension)
- Create: `packages/flutter_qa_probe/test/extensions/wait_for_idle_ext_test.dart`

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/extensions/wait_for_idle_ext_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/wait_for_idle_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wait_for_idle returns success:true on a static screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('static'))));
    await tester.pumpAndSettle();

    final resp = await WaitForIdleExtension.handle('ext.qa.wait_for_idle', {});
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(body['idle'], isTrue);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/extensions/wait_for_idle_ext.dart
import 'dart:convert';
import 'dart:developer' as developer;
import '../sync/idle_predicate.dart';

class WaitForIdleExtension {
  static const String name = 'ext.qa.wait_for_idle';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final timeoutMs = int.tryParse(params['timeout_ms'] ?? '10000') ?? 10000;
    final idle = await IdlePredicate.waitUntilIdle(
      timeout: Duration(milliseconds: timeoutMs),
    );
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'success': true, 'idle': idle}),
    );
  }
}
```

- [ ] **Step 3: Update probe.install to install the HTTP tracker**

In `packages/flutter_qa_probe/lib/src/probe.dart`, add to `install()` (after `_installed = true;`):

```dart
HttpInflightTracker.install();
```

Add the import.

- [ ] **Step 4: Register the extension** with `_register(WaitForIdleExtension.name, WaitForIdleExtension.handle);`

- [ ] **Step 5: Test, analyze, commit** with message `feat(probe): ext.qa.wait_for_idle extension`.

---

## Task 14: `ext.qa.wait_for_route` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/wait_for_route_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/extensions/wait_for_route_ext_test.dart`

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/extensions/wait_for_route_ext_test.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/flutter_qa_probe.dart';
import 'package:flutter_qa_probe/src/extensions/wait_for_route_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wait_for_route resolves once the named route becomes current', (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [FlutterQAProbe.routeTracker],
      initialRoute: '/',
      routes: {
        '/': (_) => const Scaffold(body: Text('home')),
        '/cart': (_) => const Scaffold(body: Text('cart')),
      },
    ));

    final future = WaitForRouteExtension.handle('ext.qa.wait_for_route', {
      'route': '/cart',
      'timeout_ms': '2000',
    });

    // Navigate after the wait has begun.
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/cart');
    await tester.pumpAndSettle();

    final resp = await future;
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(body['matched'], isTrue);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/extensions/wait_for_route_ext.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import '../probe.dart';

class WaitForRouteExtension {
  static const String name = 'ext.qa.wait_for_route';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final target = params['route'];
    if (target == null || target.isEmpty) {
      return _ok({'success': false, 'error': 'route required'});
    }
    final timeoutMs = int.tryParse(params['timeout_ms'] ?? '10000') ?? 10000;
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (FlutterQAProbe.routeTracker.currentRoute == target) {
        return _ok({'success': true, 'matched': true});
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _ok({
      'success': true,
      'matched': false,
      'current_route': FlutterQAProbe.routeTracker.currentRoute,
    });
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
```

- [ ] **Step 3: Register, test, commit** with message `feat(probe): ext.qa.wait_for_route extension`.

---

## Task 15: `ext.qa.wait_for_element` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/wait_for_element_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/extensions/wait_for_element_ext_test.dart`

**Context:** v1 supports matching by `label` (exact match) or `role`. Other predicates can come later. The query is one of: `{label: "Checkout"}`, `{role: "button"}`, or both.

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/extensions/wait_for_element_ext_test.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/wait_for_element_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wait_for_element finds a button by label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () {}, child: const Text('Checkout')),
      ),
    ));

    final resp = await WaitForElementExtension.handle('ext.qa.wait_for_element', {
      'label': 'Checkout',
      'timeout_ms': '1000',
    });
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(body['matched'], isTrue);
    expect(body['element_id'], startsWith('e_'));
  });

  testWidgets('wait_for_element returns matched:false after timeout', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('nothing'))));

    final resp = await WaitForElementExtension.handle('ext.qa.wait_for_element', {
      'label': 'NoSuchLabel',
      'timeout_ms': '300',
    });
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['matched'], isFalse);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/extensions/wait_for_element_ext.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import '../tree/snapshot_builder.dart';

class WaitForElementExtension {
  static const String name = 'ext.qa.wait_for_element';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final labelQuery = params['label'];
    final roleQuery = params['role'];
    if ((labelQuery == null || labelQuery.isEmpty) &&
        (roleQuery == null || roleQuery.isEmpty)) {
      return _ok({'success': false, 'error': 'label or role required'});
    }
    final timeoutMs = int.tryParse(params['timeout_ms'] ?? '5000') ?? 5000;
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      final snap = SnapshotBuilder.build();
      for (final el in snap.elements) {
        final labelOk = labelQuery == null || labelQuery.isEmpty || el.label == labelQuery;
        final roleOk = roleQuery == null || roleQuery.isEmpty || el.role == roleQuery;
        if (labelOk && roleOk) {
          return _ok({'success': true, 'matched': true, 'element_id': el.id});
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _ok({'success': true, 'matched': false});
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
```

- [ ] **Step 3: Register, test, commit** with message `feat(probe): ext.qa.wait_for_element extension`.

---

## Task 16: MCP action_tools.dart

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/tools/action_tools.dart`
- Create: `packages/flutter_qa_mcp/test/tools/action_tools_test.dart`

- [ ] **Step 1: Test (smoke — schema shape only, real exec covered by E2E in Task 18)**

```dart
// packages/flutter_qa_mcp/test/tools/action_tools_test.dart
import 'package:flutter_qa_mcp/src/tools/action_tools.dart';
import 'package:test/test.dart';

void main() {
  test('actionTools returns 7 tools with the expected names', () {
    final tools = actionTools(_FakeVm());
    final names = tools.map((t) => t.name).toSet();
    expect(names, {
      'tap', 'long_press', 'swipe', 'enter_text', 'clear_text', 'scroll', 'press_back',
    });
  });

  test('tap schema requires element_id', () {
    final tap = actionTools(_FakeVm()).firstWhere((t) => t.name == 'tap');
    expect((tap.inputSchema['required'] as List), contains('element_id'));
  });
}

class _FakeVm implements dynamic {
  noSuchMethod(Invocation i) => throw UnimplementedError();
}
```

Note: the fake VM here only needs the type — handlers won't be invoked.

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_mcp/lib/src/tools/action_tools.dart
import 'dart:convert';
import '../mcp/tool.dart';
import '../vm/client.dart';

List<Tool> actionTools(VmClient vm) => [
      Tool(
        name: 'tap',
        description: 'Synthesizes a tap at the center of the given element.',
        inputSchema: {
          'type': 'object',
          'properties': {'element_id': {'type': 'string'}},
          'required': ['element_id'],
        },
        handler: (args) async {
          final json = await vm.callExtension('ext.qa.tap', {
            'element_id': args['element_id'],
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'long_press',
        description: 'Holds a press at the center of an element for duration_ms (default 600).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'element_id': {'type': 'string'},
            'duration_ms': {'type': 'integer'},
          },
          'required': ['element_id'],
        },
        handler: (args) async {
          final json = await vm.callExtension('ext.qa.long_press', {
            'element_id': args['element_id'],
            if (args['duration_ms'] != null) 'duration_ms': args['duration_ms'].toString(),
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'swipe',
        description: 'Drags from (from_x, from_y) to (to_x, to_y) in global coordinates.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'from_x': {'type': 'number'},
            'from_y': {'type': 'number'},
            'to_x': {'type': 'number'},
            'to_y': {'type': 'number'},
            'duration_ms': {'type': 'integer'},
          },
          'required': ['from_x', 'from_y', 'to_x', 'to_y'],
        },
        handler: (args) async {
          final json = await vm.callExtension('ext.qa.swipe', {
            'from_x': args['from_x'].toString(),
            'from_y': args['from_y'].toString(),
            'to_x': args['to_x'].toString(),
            'to_y': args['to_y'].toString(),
            if (args['duration_ms'] != null) 'duration_ms': args['duration_ms'].toString(),
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'enter_text',
        description: 'Focuses the TextField at element_id and replaces its contents.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'element_id': {'type': 'string'},
            'text': {'type': 'string'},
          },
          'required': ['element_id', 'text'],
        },
        handler: (args) async {
          final json = await vm.callExtension('ext.qa.enter_text', {
            'element_id': args['element_id'],
            'text': args['text'],
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'clear_text',
        description: 'Clears the TextField at element_id.',
        inputSchema: {
          'type': 'object',
          'properties': {'element_id': {'type': 'string'}},
          'required': ['element_id'],
        },
        handler: (args) async {
          final json = await vm.callExtension('ext.qa.clear_text', {
            'element_id': args['element_id'],
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'scroll',
        description: 'Scrolls the nearest visible Scrollable (or one inside element_id).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'direction': {'type': 'string', 'enum': ['up', 'down', 'left', 'right']},
            'distance': {'type': 'number'},
            'element_id': {'type': 'string'},
          },
          'required': ['direction'],
        },
        handler: (args) async {
          final json = await vm.callExtension('ext.qa.scroll', {
            'direction': args['direction'],
            if (args['distance'] != null) 'distance': args['distance'].toString(),
            if (args['element_id'] != null) 'element_id': args['element_id'],
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'press_back',
        description: 'Equivalent to Android back button — pops the current route.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          final json = await vm.callExtension('ext.qa.press_back');
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

- [ ] **Step 3: Test + analyze**

```bash
cd packages/flutter_qa_mcp && dart test && dart analyze
```

- [ ] **Step 4: Commit** with message `feat(mcp): action tool factory (7 tools)`.

---

## Task 17: MCP sync_tools.dart

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/tools/sync_tools.dart`
- Create: `packages/flutter_qa_mcp/test/tools/sync_tools_test.dart`

- [ ] **Step 1: Test**

```dart
// packages/flutter_qa_mcp/test/tools/sync_tools_test.dart
import 'package:flutter_qa_mcp/src/tools/sync_tools.dart';
import 'package:test/test.dart';

void main() {
  test('syncTools returns 3 tools with the expected names', () {
    final tools = syncTools(_FakeVm());
    final names = tools.map((t) => t.name).toSet();
    expect(names, {'wait_for_idle', 'wait_for_route', 'wait_for_element'});
  });
}

class _FakeVm implements dynamic {
  noSuchMethod(Invocation i) => throw UnimplementedError();
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_mcp/lib/src/tools/sync_tools.dart
import 'dart:convert';
import '../mcp/tool.dart';
import '../vm/client.dart';

List<Tool> syncTools(VmClient vm) => [
      Tool(
        name: 'wait_for_idle',
        description: 'Returns when no pending frames, no running animations, and no in-flight HTTP. Bounded by timeout_ms (default 10000).',
        inputSchema: {
          'type': 'object',
          'properties': {'timeout_ms': {'type': 'integer'}},
        },
        handler: (args) async {
          final json = await vm.callExtension('ext.qa.wait_for_idle', {
            if (args['timeout_ms'] != null) 'timeout_ms': args['timeout_ms'].toString(),
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'wait_for_route',
        description: 'Returns when the current named route matches `route`. Bounded by timeout_ms.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'route': {'type': 'string'},
            'timeout_ms': {'type': 'integer'},
          },
          'required': ['route'],
        },
        handler: (args) async {
          final json = await vm.callExtension('ext.qa.wait_for_route', {
            'route': args['route'],
            if (args['timeout_ms'] != null) 'timeout_ms': args['timeout_ms'].toString(),
          });
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'wait_for_element',
        description: 'Returns when an element matching `label` and/or `role` appears in the snapshot.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'label': {'type': 'string'},
            'role': {'type': 'string'},
            'timeout_ms': {'type': 'integer'},
          },
        },
        handler: (args) async {
          final json = await vm.callExtension('ext.qa.wait_for_element', {
            if (args['label'] != null) 'label': args['label'],
            if (args['role'] != null) 'role': args['role'],
            if (args['timeout_ms'] != null) 'timeout_ms': args['timeout_ms'].toString(),
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

- [ ] **Step 3: Test, analyze, commit** with message `feat(mcp): sync tool factory (3 tools)`.

---

## Task 18: Wire action + sync tools into CLI main

**Files:**
- Modify: `packages/flutter_qa_mcp/bin/flutter_qa_mcp.dart`

- [ ] **Step 1: Update the tool list passed to McpProtocol**

```dart
// in packages/flutter_qa_mcp/bin/flutter_qa_mcp.dart, replace:
final protocol = McpProtocol(tools: perceptionTools(vm));

// with:
final protocol = McpProtocol(tools: [
  ...perceptionTools(vm),
  ...actionTools(vm),
  ...syncTools(vm),
]);
```

Add imports for `action_tools.dart` and `sync_tools.dart`.

- [ ] **Step 2: Smoke + analyze**

```bash
cd packages/flutter_qa_mcp && dart run bin/flutter_qa_mcp.dart --help && dart analyze
```

- [ ] **Step 3: Commit** with message `feat(mcp): wire action and sync tools into CLI`.

---

## Task 19: E2E drive test

**Files:**
- Create: `packages/flutter_qa_mcp/test/e2e/drive_e2e_test.dart`
- Modify: `examples/demo_app/integration_test/qa_smoke_test.dart` (extend wait window if needed)

**Context:** Boot demo_app, snapshot, find the "Go to cart" button, `tap` it, `wait_for_route('/cart')`, snapshot again, confirm the new screen has the delete button. End-to-end proof that Plan 2 works.

- [ ] **Step 1: Implement E2E**

```dart
// packages/flutter_qa_mcp/test/e2e/drive_e2e_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/tools/action_tools.dart';
import 'package:flutter_qa_mcp/src/tools/perception.dart';
import 'package:flutter_qa_mcp/src/tools/sync_tools.dart';
import 'package:flutter_qa_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  group('e2e', () {
    late Process flutter;
    late Uri vmUri;
    late VmClient vm;
    late McpProtocol protocol;

    setUpAll(() async {
      flutter = await Process.start(
        'flutter',
        ['test', 'integration_test/qa_smoke_test.dart', '--machine'],
        workingDirectory: '../../examples/demo_app',
      );
      final completer = Completer<Uri>();
      flutter.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        try {
          final m = jsonDecode(line);
          final uri = m is Map ? m['params']?['observatoryUri'] as String? : null;
          if (uri != null && !completer.isCompleted) completer.complete(Uri.parse(uri));
        } catch (_) {}
      });
      vmUri = await completer.future.timeout(const Duration(seconds: 60));
      vm = await VmClient.connect(vmUri);
      protocol = McpProtocol(tools: [
        ...perceptionTools(vm),
        ...actionTools(vm),
        ...syncTools(vm),
      ]);
    });

    tearDownAll(() async {
      await vm.dispose();
      flutter.kill();
      await flutter.exitCode;
    });

    Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args) async {
      final resp = await protocol.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': name, 'arguments': args},
      });
      final text = ((resp!['result'] as Map)['content'] as List).first['text'] as String;
      return jsonDecode(text) as Map<String, dynamic>;
    }

    test('snapshot → tap "Go to cart" → wait_for_route → snapshot finds delete buttons', () async {
      final home = await callTool('snapshot', {});
      final goToCart = (home['elements'] as List).firstWhere(
        (e) => (e as Map)['label'] == 'Go to cart',
      ) as Map;
      final id = goToCart['id'] as String;

      final tapResp = await callTool('tap', {'element_id': id});
      expect(tapResp['success'], isTrue);

      final routeResp = await callTool('wait_for_route', {
        'route': '/cart',
        'timeout_ms': 5000,
      });
      expect(routeResp['matched'], isTrue);

      final cart = await callTool('snapshot', {});
      expect(cart['route'], '/cart');
      final hasDeleteGesture = (cart['elements'] as List).any(
        (e) => (e as Map)['role'] == 'tappable',
      );
      expect(hasDeleteGesture, isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, tags: ['e2e']);
}
```

- [ ] **Step 2: Make sure the demo app pump window is wide enough**

In `examples/demo_app/integration_test/qa_smoke_test.dart`, ensure the test holds the app alive for ~60s instead of 30s (the drive test needs more time):

```dart
await tester.pump(const Duration(seconds: 60));
```

- [ ] **Step 3: Run non-e2e tests (e2e skipped by tag)**

```bash
cd packages/flutter_qa_mcp && dart test && dart analyze
cd ../flutter_qa_probe && flutter test && flutter analyze
```

All pass. E2E auto-skips.

- [ ] **Step 4: Commit** with message `test(e2e): drive flow — tap, wait_for_route, snapshot`.

---

## Done state

After all tasks land:

- The MCP server exposes 16 tools total: `snapshot`, `inspect`, `screenshot` (Plan 1) plus `tap`, `long_press`, `swipe`, `enter_text`, `clear_text`, `scroll`, `press_back`, `wait_for_idle`, `wait_for_route`, `wait_for_element` (Plan 2).
- An agent can complete a full QA flow: snapshot → identify element → tap → wait for navigation → snapshot the new screen.
- Both packages pass `flutter test` / `dart test` and `flutter analyze` / `dart analyze` clean.
- One new tagged E2E test demonstrates the snapshot → tap → wait → snapshot flow.

Plan 3 (Augmentation — persistent map, dashboard, VLM proposals, `unresolved[]`) builds on this and on the AST parser building block already in place.
