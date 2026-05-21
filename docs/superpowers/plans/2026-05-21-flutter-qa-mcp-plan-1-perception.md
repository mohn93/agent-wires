# Flutter QA MCP — Plan 1: Foundation (Perception) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the minimum end-to-end system where an LLM agent connects to a running Flutter app via MCP and can perceive its UI through `snapshot`, `inspect`, and `screenshot` tools.

**Architecture:** A Dart Flutter package (`flutter_qa_probe`) registers VM service extensions inside the app under test, exposing the denoised Element tree. A separate Dart CLI (`flutter_qa_mcp`) speaks MCP over stdio to an LLM agent and forwards calls over the Dart VM service to the probe. No actions, no persistence, no dashboard — just perception.

**Tech Stack:**
- Dart 3.5+ / Flutter 3.24+
- `package:vm_service` (VM service client)
- `package:test` (unit tests)
- `package:flutter_test` + `package:integration_test` (in-app + E2E tests)
- `package:analyzer` (Dart AST parsing for source-location proposals)
- MCP protocol implemented directly over JSON-RPC stdio (no external MCP SDK)

**Repo layout this plan creates:**

```
packages/
├── flutter_qa_probe/        # Flutter dev-dependency package
│   ├── lib/
│   │   ├── flutter_qa_probe.dart
│   │   └── src/
│   │       ├── probe.dart
│   │       ├── extensions/{snapshot,inspect,screenshot}.dart
│   │       ├── tree/{walker,classifier,role_inference,fingerprint}.dart
│   │       ├── icons/icon_role_map.dart
│   │       └── source/ast_parser.dart
│   └── test/
└── flutter_qa_mcp/          # CLI MCP server
    ├── bin/flutter_qa_mcp.dart
    ├── lib/src/
    │   ├── mcp/{transport,protocol}.dart
    │   ├── vm/client.dart
    │   └── tools/{snapshot,inspect,screenshot}.dart
    └── test/
examples/
└── demo_app/                # Tiny Flutter app for integration tests
```

---

## Task 1: Initialize repo workspace

**Files:**
- Create: `pubspec.yaml` (root, melos workspace config)
- Create: `melos.yaml`
- Create: `.gitignore`

- [ ] **Step 1: Create root workspace pubspec**

```yaml
# pubspec.yaml
name: flutter_qa_workspace
publish_to: none
environment:
  sdk: ^3.5.0
dev_dependencies:
  melos: ^6.0.0
```

- [ ] **Step 2: Create melos config**

```yaml
# melos.yaml
name: flutter_qa
packages:
  - packages/**
  - examples/**
command:
  bootstrap:
    runPubGetInParallel: true
```

- [ ] **Step 3: Create .gitignore**

```
.dart_tool/
.packages
build/
.flutter-plugins
.flutter-plugins-dependencies
pubspec.lock
.melos_tool/
.idea/
.vscode/
*.iml
```

- [ ] **Step 4: Install melos and bootstrap**

Run: `dart pub global activate melos && dart pub get`
Expected: melos installed; root `.dart_tool/` created.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml melos.yaml .gitignore
git commit -m "chore: init dart workspace with melos"
```

---

## Task 2: Initialize `flutter_qa_probe` package skeleton

**Files:**
- Create: `packages/flutter_qa_probe/pubspec.yaml`
- Create: `packages/flutter_qa_probe/lib/flutter_qa_probe.dart`
- Create: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/probe_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/probe_test.dart
import 'package:flutter_qa_probe/flutter_qa_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FlutterQAProbe.install is a no-op when called twice', () {
    FlutterQAProbe.install();
    FlutterQAProbe.install();
    expect(FlutterQAProbe.isInstalled, isTrue);
  });
}
```

- [ ] **Step 2: Create pubspec**

```yaml
# packages/flutter_qa_probe/pubspec.yaml
name: flutter_qa_probe
description: Runtime probe exposing the Flutter widget tree to QA agents over the Dart VM service.
version: 0.1.0
publish_to: none
environment:
  sdk: ^3.5.0
  flutter: ">=3.24.0"
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
flutter:
```

- [ ] **Step 3: Write the public API surface**

```dart
// packages/flutter_qa_probe/lib/flutter_qa_probe.dart
export 'src/probe.dart' show FlutterQAProbe;
```

- [ ] **Step 4: Write minimal probe implementation**

```dart
// packages/flutter_qa_probe/lib/src/probe.dart
import 'package:flutter/foundation.dart';

class FlutterQAProbe {
  FlutterQAProbe._();

  static bool _installed = false;
  static bool get isInstalled => _installed;

  static void install() {
    if (_installed) return;
    if (kReleaseMode) return; // hard no-op in release builds
    _installed = true;
  }
}
```

- [ ] **Step 5: Run tests**

Run: `cd packages/flutter_qa_probe && flutter test`
Expected: 1 test passing.

- [ ] **Step 6: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): skeleton package with install gating"
```

---

## Task 3: Register VM service extension scaffold

**Files:**
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/extension_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/extension_test.dart
import 'dart:developer' as developer;
import 'package:flutter_qa_probe/flutter_qa_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('install registers a "ext.qa.ping" extension that returns ok', () async {
    FlutterQAProbe.install();
    final reg = developer.Service.getInfo();
    expect(reg, isNotNull);
    // We can't call extensions from inside a unit test without a VM service,
    // but we can assert the extension name was registered by checking the
    // private registry through FlutterQAProbe.registeredExtensions.
    expect(FlutterQAProbe.registeredExtensions, contains('ext.qa.ping'));
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/extension_test.dart`
Expected: FAIL — `registeredExtensions` undefined.

- [ ] **Step 3: Add extension registration to probe**

```dart
// packages/flutter_qa_probe/lib/src/probe.dart
import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class FlutterQAProbe {
  FlutterQAProbe._();

  static bool _installed = false;
  static final Set<String> _registered = <String>{};

  static bool get isInstalled => _installed;
  static Set<String> get registeredExtensions => Set.unmodifiable(_registered);

  static void install() {
    if (_installed) return;
    if (kReleaseMode) return;
    _installed = true;
    _register('ext.qa.ping', (_, __) async {
      return developer.ServiceExtensionResponse.result('{"ok":true}');
    });
  }

  static void _register(
    String name,
    Future<developer.ServiceExtensionResponse> Function(
      String method, Map<String, String> params,
    ) handler,
  ) {
    developer.registerExtension(name, handler);
    _registered.add(name);
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): register ext.qa.ping extension scaffold"
```

---

## Task 4: Element tree walker (raw traversal)

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/tree/walker.dart`
- Create: `packages/flutter_qa_probe/lib/src/tree/raw_node.dart`
- Create: `packages/flutter_qa_probe/test/tree/walker_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/tree/walker_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/tree/walker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('walker yields a Text node with its string content', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('hello')),
    ));

    final nodes = ElementTreeWalker.walkFromRoot();
    final texts = nodes.where((n) => n.widgetType == 'Text').toList();

    expect(texts, isNotEmpty);
    expect(texts.first.visibleText, equals('hello'));
  });
}
```

- [ ] **Step 2: Define the RawNode record**

```dart
// packages/flutter_qa_probe/lib/src/tree/raw_node.dart
import 'package:flutter/widgets.dart';

class RawNode {
  RawNode({
    required this.element,
    required this.widgetType,
    required this.depth,
    required this.siblingIndex,
    this.visibleText,
    this.bounds,
    this.creationLocation,
  });

  final Element element;
  final String widgetType;
  final int depth;
  final int siblingIndex;
  final String? visibleText;
  final Rect? bounds;
  final String? creationLocation; // "file:line:column"
}
```

- [ ] **Step 3: Implement the walker**

```dart
// packages/flutter_qa_probe/lib/src/tree/walker.dart
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'raw_node.dart';

class ElementTreeWalker {
  static List<RawNode> walkFromRoot() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return const [];
    final out = <RawNode>[];
    _visit(root, depth: 0, siblingIndex: 0, out: out);
    return out;
  }

  static void _visit(Element e,
      {required int depth, required int siblingIndex, required List<RawNode> out}) {
    out.add(RawNode(
      element: e,
      widgetType: e.widget.runtimeType.toString(),
      depth: depth,
      siblingIndex: siblingIndex,
      visibleText: _extractText(e.widget),
      bounds: _extractBounds(e),
      creationLocation: _extractCreationLocation(e.widget),
    ));
    var idx = 0;
    e.visitChildren((child) {
      _visit(child, depth: depth + 1, siblingIndex: idx++, out: out);
    });
  }

  static String? _extractText(Widget w) {
    if (w is Text) return w.data;
    if (w is RichText) return w.text.toPlainText();
    return null;
  }

  static Rect? _extractBounds(Element e) {
    final ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize && ro.attached) {
      final origin = ro.localToGlobal(Offset.zero);
      return origin & ro.size;
    }
    return null;
  }

  static String? _extractCreationLocation(Widget w) {
    // `Widget` has a `_location` field set by --track-widget-creation.
    // Accessed via toString of the debugFillProperties / via internal API.
    // For now, use the documented `DiagnosticableTreeMixin` route.
    final diag = w.toDiagnosticsNode();
    final loc = diag.value;
    // Real implementation goes through Widget._location reflection in next task.
    return null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tree/walker_test.dart`
Expected: PASS — the Text node is found with `visibleText="hello"`.

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_qa_probe/lib/src/tree/ packages/flutter_qa_probe/test/tree/
git commit -m "feat(probe): element tree walker yielding raw nodes"
```

---

## Task 5: Extract `creationLocation` properly

**Files:**
- Modify: `packages/flutter_qa_probe/lib/src/tree/walker.dart`
- Create: `packages/flutter_qa_probe/test/tree/creation_location_test.dart`

**Context:** Flutter exposes widget creation locations through a private `_location` field on `Widget` when `--track-widget-creation` is enabled. We read it via `DiagnosticPropertiesBuilder` which Flutter populates in debug builds. The stable API: `WidgetInspectorService.instance.getSelectedWidget` uses the same data. For our purposes we use `debugFillProperties` to find a `DiagnosticsNode` named "creationLocation", or fall back to `Widget.toString(DiagnosticLevel.debug)`.

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/tree/creation_location_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/tree/walker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('walker captures creationLocation for a Text widget', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('hi'))));
    final nodes = ElementTreeWalker.walkFromRoot();
    final text = nodes.firstWhere((n) => n.widgetType == 'Text');
    expect(text.creationLocation, isNotNull);
    expect(text.creationLocation, contains('creation_location_test.dart'));
  });
}
```

- [ ] **Step 2: Update `_extractCreationLocation`**

```dart
// packages/flutter_qa_probe/lib/src/tree/walker.dart (replace _extractCreationLocation)
static String? _extractCreationLocation(Widget w) {
  final props = DiagnosticPropertiesBuilder();
  w.debugFillProperties(props);
  for (final p in props.properties) {
    if (p.name == 'creationLocation') {
      final loc = p.value;
      if (loc == null) return null;
      // _Location has .file, .line, .column getters via dynamic access.
      try {
        final d = loc as dynamic;
        return '${d.file}:${d.line}:${d.column}';
      } catch (_) {
        return loc.toString();
      }
    }
  }
  return null;
}
```

Note: this relies on `--track-widget-creation` being enabled, which is default in `flutter test` and debug runs. Document this in the package README in a later task.

- [ ] **Step 3: Run tests**

Run: `flutter test test/tree/creation_location_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): capture widget creationLocation"
```

---

## Task 6: Promote/skip/collapse classifier

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/tree/classifier.dart`
- Create: `packages/flutter_qa_probe/test/tree/classifier_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/tree/classifier_test.dart
import 'package:flutter_qa_probe/src/tree/classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ElevatedButton is promoted', () {
    expect(Classifier.classifyByType('ElevatedButton'), Classification.promote);
  });
  test('Padding is skipped', () {
    expect(Classifier.classifyByType('Padding'), Classification.skip);
  });
  test('Text is collapsed into parent', () {
    expect(Classifier.classifyByType('Text'), Classification.collapse);
  });
  test('Unknown widgets default to skip', () {
    expect(Classifier.classifyByType('SomeRandomCustomWidget'), Classification.skip);
  });
}
```

- [ ] **Step 2: Implement the classifier**

```dart
// packages/flutter_qa_probe/lib/src/tree/classifier.dart
enum Classification { promote, skip, collapse }

class Classifier {
  static const Set<String> _promote = {
    'ElevatedButton', 'TextButton', 'OutlinedButton', 'IconButton',
    'FloatingActionButton', 'TextField', 'TextFormField',
    'Switch', 'Checkbox', 'Radio', 'Slider',
    'DropdownButton', 'PopupMenuButton',
    'AppBar', 'BottomNavigationBar', 'Tab', 'Drawer',
    'Dialog', 'AlertDialog', 'BottomSheet', 'SnackBar',
    'ListTile', 'GestureDetector', 'InkWell', 'Listener',
  };

  static const Set<String> _collapse = {
    'Text', 'RichText', 'Icon', 'ImageIcon',
  };

  static const Set<String> _skip = {
    'Padding', 'Center', 'Align', 'SizedBox', 'Container',
    'Expanded', 'Flexible', 'Row', 'Column', 'Stack', 'Wrap',
    'ConstrainedBox', 'FractionallySizedBox',
    'Theme', 'MediaQuery', 'DefaultTextStyle', 'IconTheme',
    'Directionality', 'Material',
    'Builder', 'LayoutBuilder', 'AnimatedBuilder',
    'ValueListenableBuilder', 'StreamBuilder',
  };

  static Classification classifyByType(String widgetType) {
    if (_promote.contains(widgetType)) return Classification.promote;
    if (_collapse.contains(widgetType)) return Classification.collapse;
    return Classification.skip;
  }
}
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/tree/classifier_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 4: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): promote/skip/collapse classifier"
```

---

## Task 7: Detect handlers on GestureDetector / InkWell

**Files:**
- Modify: `packages/flutter_qa_probe/lib/src/tree/classifier.dart`
- Create: `packages/flutter_qa_probe/test/tree/handler_detection_test.dart`

**Context:** `GestureDetector` and `InkWell` only count as interactive if they have a non-null `onTap` / `onLongPress` / etc. Pure decorative wrappers should be skipped.

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/tree/handler_detection_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/tree/classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GestureDetector with onTap is promoted', () {
    final w = GestureDetector(onTap: () {}, child: const SizedBox());
    expect(Classifier.classify(w), Classification.promote);
  });
  test('GestureDetector without handlers is skipped', () {
    final w = GestureDetector(child: const SizedBox());
    expect(Classifier.classify(w), Classification.skip);
  });
  test('InkWell with onTap is promoted', () {
    final w = InkWell(onTap: () {}, child: const SizedBox());
    expect(Classifier.classify(w), Classification.promote);
  });
}
```

- [ ] **Step 2: Add `classify(Widget)` method**

```dart
// add to Classifier in classifier.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

// ... existing code ...

static Classification classify(Widget w) {
  final type = w.runtimeType.toString();
  if (w is GestureDetector) {
    return _hasGestureHandler(w) ? Classification.promote : Classification.skip;
  }
  if (w is InkWell) {
    return (w.onTap != null || w.onLongPress != null || w.onDoubleTap != null)
        ? Classification.promote
        : Classification.skip;
  }
  return classifyByType(type);
}

static bool _hasGestureHandler(GestureDetector g) {
  return g.onTap != null ||
      g.onLongPress != null ||
      g.onDoubleTap != null ||
      g.onPanStart != null ||
      g.onHorizontalDragStart != null ||
      g.onVerticalDragStart != null;
}
```

- [ ] **Step 3: Run tests**

Run: `flutter test`
Expected: all tests pass including new handler-detection tests.

- [ ] **Step 4: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): handler-aware classification for GestureDetector/InkWell"
```

---

## Task 8: Icon → role map

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/icons/icon_role_map.dart`
- Create: `packages/flutter_qa_probe/test/icons/icon_role_map_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/icons/icon_role_map_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/icons/icon_role_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shopping_cart maps to "cart"', () {
    expect(IconRoleMap.roleFor(Icons.shopping_cart), 'cart');
  });
  test('delete maps to "delete"', () {
    expect(IconRoleMap.roleFor(Icons.delete), 'delete');
  });
  test('arrow_back maps to "back"', () {
    expect(IconRoleMap.roleFor(Icons.arrow_back), 'back');
  });
  test('close maps to "dismiss"', () {
    expect(IconRoleMap.roleFor(Icons.close), 'dismiss');
  });
  test('unknown icon returns null', () {
    expect(IconRoleMap.roleFor(const IconData(0x99999)), isNull);
  });
}
```

- [ ] **Step 2: Implement the map**

```dart
// packages/flutter_qa_probe/lib/src/icons/icon_role_map.dart
import 'package:flutter/material.dart';

class IconRoleMap {
  // Keyed by IconData codepoint. Curated from common Material icons.
  // Not exhaustive; extend as patterns emerge from real apps.
  static final Map<int, String> _byCodepoint = <int, String>{
    Icons.shopping_cart.codePoint: 'cart',
    Icons.shopping_bag.codePoint: 'cart',
    Icons.delete.codePoint: 'delete',
    Icons.delete_outline.codePoint: 'delete',
    Icons.arrow_back.codePoint: 'back',
    Icons.arrow_back_ios.codePoint: 'back',
    Icons.close.codePoint: 'dismiss',
    Icons.cancel.codePoint: 'dismiss',
    Icons.menu.codePoint: 'menu',
    Icons.search.codePoint: 'search',
    Icons.settings.codePoint: 'settings',
    Icons.add.codePoint: 'add',
    Icons.edit.codePoint: 'edit',
    Icons.favorite.codePoint: 'favorite',
    Icons.favorite_border.codePoint: 'favorite',
    Icons.share.codePoint: 'share',
    Icons.home.codePoint: 'home',
    Icons.person.codePoint: 'profile',
    Icons.account_circle.codePoint: 'profile',
    Icons.notifications.codePoint: 'notifications',
    Icons.more_vert.codePoint: 'more',
    Icons.more_horiz.codePoint: 'more',
    Icons.check.codePoint: 'confirm',
    Icons.check_circle.codePoint: 'confirm',
  };

  static String? roleFor(IconData icon) => _byCodepoint[icon.codePoint];
}
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/icons/icon_role_map_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 4: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): IconData codepoint → role map"
```

---

## Task 9: Role inference (label extraction from a promoted subtree)

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/tree/role_inference.dart`
- Create: `packages/flutter_qa_probe/test/tree/role_inference_test.dart`

**Context:** Given a promoted element, walk its subtree looking for text and icons; produce a `label` and `role`. Text wins over icon when both exist.

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/tree/role_inference_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/tree/role_inference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('button with Text child gets label from text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ElevatedButton(onPressed: () {}, child: const Text('Checkout'))),
    ));
    final button = tester.element(find.byType(ElevatedButton));
    final inf = RoleInference.infer(button);
    expect(inf.label, 'Checkout');
    expect(inf.role, 'button');
    expect(inf.labelSource, LabelSource.textChild);
  });

  testWidgets('IconButton with cart icon and no text gets role "cart"', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: IconButton(onPressed: () {}, icon: const Icon(Icons.shopping_cart))),
    ));
    final btn = tester.element(find.byType(IconButton));
    final inf = RoleInference.infer(btn);
    expect(inf.label, 'cart');
    expect(inf.role, 'button');
    expect(inf.labelSource, LabelSource.icon);
  });
}
```

- [ ] **Step 2: Implement the inference**

```dart
// packages/flutter_qa_probe/lib/src/tree/role_inference.dart
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../icons/icon_role_map.dart';

enum LabelSource { textChild, icon, semantics, sourceLocation, none }

class InferredRole {
  InferredRole({required this.role, required this.label, required this.labelSource});
  final String role;
  final String? label;
  final LabelSource labelSource;
}

class RoleInference {
  static const Map<String, String> _roleByType = {
    'ElevatedButton': 'button',
    'TextButton': 'button',
    'OutlinedButton': 'button',
    'IconButton': 'button',
    'FloatingActionButton': 'button',
    'TextField': 'textfield',
    'TextFormField': 'textfield',
    'Switch': 'switch',
    'Checkbox': 'checkbox',
    'Radio': 'radio',
    'Slider': 'slider',
    'ListTile': 'list_item',
    'AppBar': 'appbar',
    'Tab': 'tab',
    'GestureDetector': 'tappable',
    'InkWell': 'tappable',
  };

  static InferredRole infer(Element e) {
    final type = e.widget.runtimeType.toString();
    final role = _roleByType[type] ?? 'unknown';

    final text = _firstDescendantText(e);
    if (text != null && text.isNotEmpty) {
      return InferredRole(role: role, label: text, labelSource: LabelSource.textChild);
    }

    final iconRole = _firstDescendantIconRole(e);
    if (iconRole != null) {
      return InferredRole(role: role, label: iconRole, labelSource: LabelSource.icon);
    }

    return InferredRole(role: role, label: null, labelSource: LabelSource.none);
  }

  static String? _firstDescendantText(Element root) {
    String? found;
    void visit(Element e) {
      if (found != null) return;
      final w = e.widget;
      if (w is Text && (w.data?.isNotEmpty ?? false)) {
        found = w.data;
        return;
      }
      if (w is RichText) {
        final s = w.text.toPlainText();
        if (s.isNotEmpty) {
          found = s;
          return;
        }
      }
      e.visitChildren(visit);
    }
    root.visitChildren(visit);
    return found;
  }

  static String? _firstDescendantIconRole(Element root) {
    String? found;
    void visit(Element e) {
      if (found != null) return;
      final w = e.widget;
      if (w is Icon && w.icon != null) {
        final r = IconRoleMap.roleFor(w.icon!);
        if (r != null) {
          found = r;
          return;
        }
      }
      e.visitChildren(visit);
    }
    root.visitChildren(visit);
    return found;
  }
}
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/tree/role_inference_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 4: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): role+label inference from element subtree"
```

---

## Task 10: Fingerprint computation

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/tree/fingerprint.dart`
- Create: `packages/flutter_qa_probe/test/tree/fingerprint_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/tree/fingerprint_test.dart
import 'package:flutter_qa_probe/src/tree/fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identical inputs produce identical fingerprints', () {
    final a = Fingerprint.compute(
      creationLocation: 'lib/cart.dart:42:8',
      widgetType: 'ElevatedButton',
      ancestorTypes: ['Scaffold', 'Column'],
      siblingIndex: 0,
      visibleText: 'Checkout',
    );
    final b = Fingerprint.compute(
      creationLocation: 'lib/cart.dart:42:8',
      widgetType: 'ElevatedButton',
      ancestorTypes: ['Scaffold', 'Column'],
      siblingIndex: 0,
      visibleText: 'Checkout',
    );
    expect(a, b);
    expect(a, matches(RegExp(r'^f_[a-f0-9]{12}$')));
  });

  test('different sibling indices produce different fingerprints', () {
    final a = Fingerprint.compute(
      creationLocation: 'lib/cart.dart:42:8',
      widgetType: 'ElevatedButton',
      ancestorTypes: ['Scaffold', 'ListView'],
      siblingIndex: 0,
      visibleText: 'Item',
    );
    final b = Fingerprint.compute(
      creationLocation: 'lib/cart.dart:42:8',
      widgetType: 'ElevatedButton',
      ancestorTypes: ['Scaffold', 'ListView'],
      siblingIndex: 1,
      visibleText: 'Item',
    );
    expect(a, isNot(b));
  });
}
```

- [ ] **Step 2: Implement fingerprint**

```dart
// packages/flutter_qa_probe/lib/src/tree/fingerprint.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

class Fingerprint {
  static String compute({
    required String? creationLocation,
    required String widgetType,
    required List<String> ancestorTypes,
    required int siblingIndex,
    required String? visibleText,
  }) {
    final raw = StringBuffer()
      ..write(creationLocation ?? '?')
      ..write('|')
      ..write(widgetType)
      ..write('|')
      ..write(ancestorTypes.join('>'))
      ..write('|')
      ..write(siblingIndex)
      ..write('|')
      ..write(visibleText ?? '');
    final digest = sha1.convert(utf8.encode(raw.toString())).toString();
    return 'f_${digest.substring(0, 12)}';
  }
}
```

- [ ] **Step 3: Add `crypto` dependency**

Edit `packages/flutter_qa_probe/pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  crypto: ^3.0.3
```

Run: `flutter pub get`

- [ ] **Step 4: Run tests**

Run: `flutter test test/tree/fingerprint_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): deterministic element fingerprinting"
```

---

## Task 11: Source-location AST parser (building block for Plan 3)

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/source/ast_parser.dart`
- Create: `packages/flutter_qa_probe/test/source/ast_parser_test.dart`
- Create: `packages/flutter_qa_probe/test/fixtures/sample_widget_file.dart`

**Context:** Plan 3 will use this to produce `source_location` label proposals for unresolved elements (per the design spec's augmentation loop). We build and test it in isolation here so Plan 3 can plug it into the snapshot builder without re-doing the AST work. Not wired into `SnapshotBuilder` in Plan 1.

Given `lib/cart_screen.dart:127:14`, find the enclosing function or method name via `package:analyzer`.

- [ ] **Step 1: Add analyzer dependency**

Edit `packages/flutter_qa_probe/pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  crypto: ^3.0.3
  analyzer: ^6.4.0
  path: ^1.9.0
```

Run: `flutter pub get`

- [ ] **Step 2: Create the fixture file**

```dart
// packages/flutter_qa_probe/test/fixtures/sample_widget_file.dart
// Used as a parse target only. Not executed.
class CartScreen {
  Widget _buildRemoveButton() {
    return GestureDetector(
      onTap: () {},
      child: const Icon(Icons.delete),
    );
  }
}
```

- [ ] **Step 3: Write the failing test**

```dart
// packages/flutter_qa_probe/test/source/ast_parser_test.dart
import 'package:flutter_qa_probe/src/source/ast_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns enclosing method name for an offset inside the method body', () {
    const path = 'test/fixtures/sample_widget_file.dart';
    // The GestureDetector starts on line 5; column doesn't matter much for enclosing scope.
    final name = AstParser.enclosingFunction(filePath: path, line: 5, column: 12);
    expect(name, '_buildRemoveButton');
  });

  test('returns null when file does not exist', () {
    final name = AstParser.enclosingFunction(filePath: 'nope.dart', line: 1, column: 1);
    expect(name, isNull);
  });
}
```

- [ ] **Step 4: Implement the parser**

```dart
// packages/flutter_qa_probe/lib/src/source/ast_parser.dart
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class AstParser {
  static final Map<String, _ParsedFile> _cache = {};

  static String? enclosingFunction({
    required String filePath,
    required int line,
    required int column,
  }) {
    final parsed = _load(filePath);
    if (parsed == null) return null;
    final offset = parsed.offsetFor(line, column);
    if (offset == null) return null;
    final visitor = _EnclosingFunctionVisitor(offset);
    parsed.unit.visitChildren(visitor);
    return visitor.found;
  }

  static _ParsedFile? _load(String filePath) {
    final cached = _cache[filePath];
    if (cached != null) return cached;
    final file = File(filePath);
    if (!file.existsSync()) return null;
    final source = file.readAsStringSync();
    final result = parseString(content: source, throwIfDiagnostics: false);
    final pf = _ParsedFile(result.unit, _LineOffsets(source));
    _cache[filePath] = pf;
    return pf;
  }
}

class _ParsedFile {
  _ParsedFile(this.unit, this.offsets);
  final CompilationUnit unit;
  final _LineOffsets offsets;
  int? offsetFor(int line, int column) => offsets.offsetFor(line, column);
}

class _LineOffsets {
  _LineOffsets(String source) {
    int offset = 0;
    _starts.add(0);
    for (final ch in source.codeUnits) {
      offset++;
      if (ch == 10 /* \n */) _starts.add(offset);
    }
  }
  final List<int> _starts = [];
  int? offsetFor(int line, int column) {
    final idx = line - 1;
    if (idx < 0 || idx >= _starts.length) return null;
    return _starts[idx] + (column - 1);
  }
}

class _EnclosingFunctionVisitor extends RecursiveAstVisitor<void> {
  _EnclosingFunctionVisitor(this.offset);
  final int offset;
  String? found;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (_contains(node)) found = node.name.lexeme;
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (_contains(node)) found = node.name.lexeme;
    super.visitFunctionDeclaration(node);
  }

  bool _contains(AstNode node) => offset >= node.offset && offset <= node.end;
}
```

- [ ] **Step 5: Run tests**

Run: `flutter test test/source/ast_parser_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): AST parser extracts enclosing function name"
```

---

## Task 12: Denoised snapshot builder (puts it all together)

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/tree/snapshot_builder.dart`
- Create: `packages/flutter_qa_probe/lib/src/tree/element_record.dart`
- Create: `packages/flutter_qa_probe/test/tree/snapshot_builder_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/tree/snapshot_builder_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/tree/snapshot_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('snapshot returns one element for a labeled ElevatedButton', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(onPressed: () {}, child: const Text('Checkout')),
        ),
      ),
    ));

    final snap = SnapshotBuilder.build();
    final buttons = snap.elements.where((e) => e.widgetType == 'ElevatedButton').toList();
    expect(buttons, hasLength(1));
    expect(buttons.first.label, 'Checkout');
    expect(buttons.first.role, 'button');
    expect(buttons.first.fingerprint, startsWith('f_'));
  });

  testWidgets('Padding and Center do not appear in elements', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Padding(padding: EdgeInsets.all(8), child: Center(child: Text('hi'))),
    ));
    final snap = SnapshotBuilder.build();
    expect(snap.elements.where((e) => e.widgetType == 'Padding'), isEmpty);
    expect(snap.elements.where((e) => e.widgetType == 'Center'), isEmpty);
  });
}
```

- [ ] **Step 2: Define ElementRecord**

```dart
// packages/flutter_qa_probe/lib/src/tree/element_record.dart
import 'package:flutter/widgets.dart';

class ElementRecord {
  ElementRecord({
    required this.id,
    required this.fingerprint,
    required this.widgetType,
    required this.role,
    required this.label,
    required this.labelSource,
    required this.bounds,
    required this.creationLocation,
    required this.enabled,
  });

  final String id;
  final String fingerprint;
  final String widgetType;
  final String role;
  final String? label;
  final String labelSource; // matches LabelSource enum name
  final Rect? bounds;
  final String? creationLocation;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fingerprint': fingerprint,
        'widget_type': widgetType,
        'role': role,
        if (label != null) 'label': label,
        'label_source': labelSource,
        if (bounds != null)
          'bounds': {
            'x': bounds!.left,
            'y': bounds!.top,
            'w': bounds!.width,
            'h': bounds!.height,
          },
        if (creationLocation != null) 'creation_location': creationLocation,
        'enabled': enabled,
      };
}

class SnapshotRecord {
  SnapshotRecord({required this.route, required this.viewport, required this.elements});
  final String? route;
  final Size viewport;
  final List<ElementRecord> elements;

  Map<String, dynamic> toJson() => {
        if (route != null) 'route': route,
        'viewport': {'w': viewport.width, 'h': viewport.height},
        'elements': elements.map((e) => e.toJson()).toList(),
      };
}
```

- [ ] **Step 3: Implement SnapshotBuilder**

```dart
// packages/flutter_qa_probe/lib/src/tree/snapshot_builder.dart
import 'package:flutter/widgets.dart';
import 'classifier.dart';
import 'element_record.dart';
import 'fingerprint.dart';
import 'role_inference.dart';
import 'walker.dart';

class SnapshotBuilder {
  static SnapshotRecord build() {
    final raw = ElementTreeWalker.walkFromRoot();
    final elements = <ElementRecord>[];

    for (final node in raw) {
      final cls = Classifier.classify(node.element.widget);
      if (cls != Classification.promote) continue;
      if (node.bounds == null) continue; // off-screen / not laid out

      final ancestors = _ancestorTypes(node.element);
      final inferred = RoleInference.infer(node.element);
      final fp = Fingerprint.compute(
        creationLocation: node.creationLocation,
        widgetType: node.widgetType,
        ancestorTypes: ancestors,
        siblingIndex: node.siblingIndex,
        visibleText: inferred.label,
      );

      elements.add(ElementRecord(
        id: 'e_${elements.length}',
        fingerprint: fp,
        widgetType: node.widgetType,
        role: inferred.role,
        label: inferred.label,
        labelSource: inferred.labelSource.name,
        bounds: node.bounds,
        creationLocation: node.creationLocation,
        enabled: true, // refined in a later task
      ));
    }

    final media = MediaQueryData.fromView(WidgetsBinding.instance.platformDispatcher.views.first);
    return SnapshotRecord(
      route: null, // wired up in Task 14
      viewport: media.size,
      elements: elements,
    );
  }

  static List<String> _ancestorTypes(Element e) {
    final out = <String>[];
    e.visitAncestorElements((a) {
      out.add(a.widget.runtimeType.toString());
      return out.length < 10; // cap to keep fingerprints stable across deep theme nesting
    });
    return out.reversed.toList();
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/tree/snapshot_builder_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): SnapshotBuilder combining walker, classifier, inference, fingerprint"
```

---

## Task 13: Track current route with NavigatorObserver

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/navigation/route_tracker.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Modify: `packages/flutter_qa_probe/lib/src/tree/snapshot_builder.dart`
- Create: `packages/flutter_qa_probe/test/navigation/route_tracker_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/navigation/route_tracker_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/navigation/route_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tracker reports the current named route', (tester) async {
    final tracker = RouteTracker();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [tracker],
      initialRoute: '/',
      routes: {
        '/': (_) => const Scaffold(body: Text('root')),
        '/cart': (_) => const Scaffold(body: Text('cart')),
      },
    ));
    expect(tracker.currentRoute, '/');

    // Navigate.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/cart');
    await tester.pumpAndSettle();

    expect(tracker.currentRoute, '/cart');
  });
}
```

- [ ] **Step 2: Implement RouteTracker**

```dart
// packages/flutter_qa_probe/lib/src/navigation/route_tracker.dart
import 'package:flutter/widgets.dart';

class RouteTracker extends NavigatorObserver {
  String? _current;
  String? get currentRoute => _current;

  @override
  void didPush(Route route, Route? previousRoute) {
    _current = route.settings.name ?? _current;
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _current = previousRoute?.settings.name ?? _current;
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _current = newRoute?.settings.name ?? _current;
  }
}
```

- [ ] **Step 3: Wire tracker into probe singleton**

```dart
// add to probe.dart
import 'navigation/route_tracker.dart';

class FlutterQAProbe {
  // ...
  static final RouteTracker _routeTracker = RouteTracker();
  static RouteTracker get routeTracker => _routeTracker;
  // ... in install(), no extra wiring needed; user attaches observer in their MaterialApp.
}
```

- [ ] **Step 4: Document the observer wiring**

Add to `packages/flutter_qa_probe/lib/flutter_qa_probe.dart`:
```dart
export 'src/probe.dart' show FlutterQAProbe;
export 'src/navigation/route_tracker.dart' show RouteTracker;
```

Note in the package README (created in Task 24): users must add `FlutterQAProbe.routeTracker` to their `MaterialApp.navigatorObservers` for route tracking to work.

- [ ] **Step 5: Update SnapshotBuilder to include route**

```dart
// snapshot_builder.dart, replace route: null with:
import '../probe.dart';
// ...
return SnapshotRecord(
  route: FlutterQAProbe.routeTracker.currentRoute,
  // ...
);
```

- [ ] **Step 6: Run tests**

Run: `flutter test`
Expected: all passing.

- [ ] **Step 7: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): NavigatorObserver-based route tracking"
```

---

## Task 14: `ext.qa.snapshot` VM service extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/snapshot_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/extensions/snapshot_ext_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/extensions/snapshot_ext_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/snapshot_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('handleSnapshot returns JSON with route and elements', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () {}, child: const Text('Tap me')),
      ),
    ));

    final resp = await SnapshotExtension.handle('ext.qa.snapshot', const {});
    expect(resp.isError, isFalse);
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['elements'], isA<List>());
    final hasButton = (body['elements'] as List)
        .any((e) => (e as Map)['widget_type'] == 'ElevatedButton');
    expect(hasButton, isTrue);
  });
}
```

- [ ] **Step 2: Implement the extension handler**

```dart
// packages/flutter_qa_probe/lib/src/extensions/snapshot_ext.dart
import 'dart:convert';
import 'dart:developer' as developer;
import '../tree/snapshot_builder.dart';

class SnapshotExtension {
  static const String name = 'ext.qa.snapshot';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final snap = SnapshotBuilder.build();
      return developer.ServiceExtensionResponse.result(jsonEncode(snap.toJson()));
    } catch (e, st) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': e.toString(), 'stack': st.toString()}),
      );
    }
  }
}
```

- [ ] **Step 3: Register the extension in `FlutterQAProbe.install`**

```dart
// probe.dart, in install():
_register(SnapshotExtension.name, SnapshotExtension.handle);
```

(Add the import.)

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: all passing.

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): ext.qa.snapshot VM service extension"
```

---

## Task 15: `ext.qa.inspect` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/inspect_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`
- Create: `packages/flutter_qa_probe/test/extensions/inspect_ext_test.dart`

**Context:** `inspect` takes an `element_id` from a recent snapshot and returns the full widget chain (ancestor types up to MaterialApp) plus all the `Diagnosticable` properties of the target widget. We resolve `element_id` by re-walking the tree and indexing by `id`. (Future work: cache by snapshot-id; for v1, re-walk is fine.)

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_probe/test/extensions/inspect_ext_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/inspect_ext.dart';
import 'package:flutter_qa_probe/src/extensions/snapshot_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inspect returns properties for a known element id', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ElevatedButton(onPressed: () {}, child: const Text('Go'))),
    ));

    final snapResp = await SnapshotExtension.handle('ext.qa.snapshot', const {});
    final snap = jsonDecode(snapResp.result!) as Map<String, dynamic>;
    final id = ((snap['elements'] as List).first as Map)['id'] as String;

    final resp = await InspectExtension.handle('ext.qa.inspect', {'element_id': id});
    expect(resp.isError, isFalse);
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['ancestor_types'], isA<List>());
    expect(body['widget_type'], isNotNull);
  });

  test('inspect with missing element_id returns error', () async {
    final resp = await InspectExtension.handle('ext.qa.inspect', const {});
    expect(resp.isError, isTrue);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_probe/lib/src/extensions/inspect_ext.dart
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/widgets.dart';
import '../tree/classifier.dart';
import '../tree/walker.dart';

class InspectExtension {
  static const String name = 'ext.qa.inspect';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final id = params['element_id'];
    if (id == null || id.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        jsonEncode({'error': 'element_id required'}),
      );
    }

    final raw = ElementTreeWalker.walkFromRoot();
    final promoted = raw
        .where((n) => Classifier.classify(n.element.widget) == Classification.promote)
        .toList();
    final idx = int.tryParse(id.replaceFirst('e_', '')) ?? -1;
    if (idx < 0 || idx >= promoted.length) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': 'element not found'}),
      );
    }

    final node = promoted[idx];
    final w = node.element.widget;
    final props = <String, String>{};
    final builder = DiagnosticPropertiesBuilder();
    w.debugFillProperties(builder);
    for (final p in builder.properties) {
      props[p.name ?? '?'] = p.value?.toString() ?? '';
    }

    final ancestors = <String>[];
    node.element.visitAncestorElements((a) {
      ancestors.add(a.widget.runtimeType.toString());
      return ancestors.length < 20;
    });

    return developer.ServiceExtensionResponse.result(jsonEncode({
      'widget_type': node.widgetType,
      'creation_location': node.creationLocation,
      'ancestor_types': ancestors,
      'properties': props,
    }));
  }
}
```

- [ ] **Step 3: Register in install**

Add `_register(InspectExtension.name, InspectExtension.handle);` in `FlutterQAProbe.install`.

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: all passing.

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): ext.qa.inspect extension"
```

---

## Task 16: `ext.qa.screenshot` extension

**Files:**
- Create: `packages/flutter_qa_probe/lib/src/extensions/screenshot_ext.dart`
- Modify: `packages/flutter_qa_probe/lib/src/probe.dart`

**Context:** Use `RendererBinding.instance.renderViews.first` to capture the root render layer to a PNG via `RenderRepaintBoundary.toImage`. The root view is a `RenderView`, not a `RenderRepaintBoundary`, so we walk to the first repaint boundary descendant. Cheaper alternative: `flutter_test`'s `takeScreenshot` API in test mode, but at runtime we use the render pipeline directly.

- [ ] **Step 1: Implement**

```dart
// packages/flutter_qa_probe/lib/src/extensions/screenshot_ext.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ScreenshotExtension {
  static const String name = 'ext.qa.screenshot';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final boundary = _findRootRepaintBoundary();
      if (boundary == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          jsonEncode({'error': 'no RepaintBoundary found'}),
        );
      }
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          jsonEncode({'error': 'failed to encode PNG'}),
        );
      }
      final b64 = base64Encode(bytes.buffer.asUint8List());
      return developer.ServiceExtensionResponse.result(jsonEncode({
        'format': 'png',
        'width': image.width,
        'height': image.height,
        'data_base64': b64,
      }));
    } catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': e.toString()}),
      );
    }
  }

  static RenderRepaintBoundary? _findRootRepaintBoundary() {
    RenderRepaintBoundary? found;
    void walk(RenderObject ro) {
      if (found != null) return;
      if (ro is RenderRepaintBoundary) {
        found = ro;
        return;
      }
      ro.visitChildren(walk);
    }
    final root = WidgetsBinding.instance.rootElement?.renderObject;
    if (root != null) walk(root);
    return found;
  }
}
```

- [ ] **Step 2: Register in install**

`_register(ScreenshotExtension.name, ScreenshotExtension.handle);`

- [ ] **Step 3: Smoke-test in widget test**

```dart
// add to test/extensions/screenshot_ext_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/screenshot_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('screenshot returns base64 PNG bytes', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    final resp = await ScreenshotExtension.handle('ext.qa.screenshot', const {});
    expect(resp.isError, isFalse);
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['format'], 'png');
    expect((body['data_base64'] as String).length, greaterThan(100));
  });
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: all passing.

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_qa_probe/
git commit -m "feat(probe): ext.qa.screenshot extension returning base64 PNG"
```

---

## Task 17: Initialize `flutter_qa_mcp` CLI package

**Files:**
- Create: `packages/flutter_qa_mcp/pubspec.yaml`
- Create: `packages/flutter_qa_mcp/bin/flutter_qa_mcp.dart`
- Create: `packages/flutter_qa_mcp/lib/src/version.dart`

- [ ] **Step 1: Create pubspec**

```yaml
# packages/flutter_qa_mcp/pubspec.yaml
name: flutter_qa_mcp
description: MCP server bridging an LLM agent to a running Flutter app via the Dart VM service.
version: 0.1.0
publish_to: none
environment:
  sdk: ^3.5.0
dependencies:
  args: ^2.5.0
  vm_service: ^14.0.0
dev_dependencies:
  test: ^1.25.0
  lints: ^4.0.0
executables:
  flutter_qa_mcp: flutter_qa_mcp
```

- [ ] **Step 2: Create version file**

```dart
// packages/flutter_qa_mcp/lib/src/version.dart
const String packageVersion = '0.1.0';
```

- [ ] **Step 3: Create CLI entry stub**

```dart
// packages/flutter_qa_mcp/bin/flutter_qa_mcp.dart
import 'dart:io';
import 'package:args/args.dart';
import 'package:flutter_qa_mcp/src/version.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('attach', help: 'VM service URI to attach to (ws://...)')
    ..addFlag('version', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } catch (e) {
    stderr.writeln('argument error: $e');
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (parsed['help'] as bool) {
    stdout.writeln('flutter_qa_mcp — MCP server for Flutter QA agents\n');
    stdout.writeln(parser.usage);
    return;
  }
  if (parsed['version'] as bool) {
    stdout.writeln(packageVersion);
    return;
  }
  stderr.writeln('not yet implemented');
  exit(70);
}
```

- [ ] **Step 4: Run `dart pub get` and verify CLI parses**

```bash
cd packages/flutter_qa_mcp && dart pub get && dart run bin/flutter_qa_mcp.dart --version
```
Expected: prints `0.1.0`.

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): initialize CLI package skeleton"
```

---

## Task 18: JSON-RPC over stdio transport

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/mcp/transport.dart`
- Create: `packages/flutter_qa_mcp/test/mcp/transport_test.dart`

**Context:** MCP transport is newline-delimited JSON-RPC 2.0 messages over stdin/stdout. We implement a minimal `StdioTransport` with `Stream<Map<String, dynamic>> incoming` and `void send(Map<String, dynamic>)`. Real MCP uses Content-Length framed messages over stdio; for v1 we implement **line-delimited JSON** which is what the MCP spec calls "stdio" transport (one JSON object per line). Verified against the MCP 2025-06-18 spec.

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_mcp/test/mcp/transport_test.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_qa_mcp/src/mcp/transport.dart';
import 'package:test/test.dart';

void main() {
  test('decodes single-line JSON messages from stdin stream', () async {
    final input = Stream<List<int>>.fromIterable([
      utf8.encode('{"jsonrpc":"2.0","id":1,"method":"ping"}\n'),
      utf8.encode('{"jsonrpc":"2.0","id":2,"method":"pong"}\n'),
    ]);
    final outBuf = <List<int>>[];
    final transport = StdioTransport(input: input, output: _CollectSink(outBuf));
    final received = await transport.incoming.take(2).toList();
    expect(received[0]['method'], 'ping');
    expect(received[1]['method'], 'pong');
  });

  test('send writes a single line of JSON', () async {
    final outBuf = <List<int>>[];
    final transport = StdioTransport(
      input: const Stream.empty(),
      output: _CollectSink(outBuf),
    );
    transport.send({'jsonrpc': '2.0', 'id': 1, 'result': {'ok': true}});
    await Future<void>.delayed(Duration.zero);
    final text = utf8.decode(outBuf.expand((b) => b).toList());
    expect(text.trim(), '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}');
  });
}

class _CollectSink implements StreamSink<List<int>> {
  _CollectSink(this.buf);
  final List<List<int>> buf;
  @override
  void add(List<int> data) => buf.add(data);
  @override
  Future close() async {}
  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final c in stream) buf.add(c);
  }
  @override
  void addError(error, [StackTrace? st]) {}
  @override
  Future get done => Future.value();
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_mcp/lib/src/mcp/transport.dart
import 'dart:async';
import 'dart:convert';

class StdioTransport {
  StdioTransport({required Stream<List<int>> input, required StreamSink<List<int>> output})
      : _output = output {
    _incoming = input
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((l) => l.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>);
  }

  late final Stream<Map<String, dynamic>> _incoming;
  final StreamSink<List<int>> _output;

  Stream<Map<String, dynamic>> get incoming => _incoming;

  void send(Map<String, dynamic> message) {
    _output.add(utf8.encode('${jsonEncode(message)}\n'));
  }
}
```

- [ ] **Step 3: Run tests**

Run: `cd packages/flutter_qa_mcp && dart test`
Expected: 2 tests passing.

- [ ] **Step 4: Commit**

```bash
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): newline-delimited JSON-RPC stdio transport"
```

---

## Task 19: MCP protocol handler (initialize + tools/list + tools/call)

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/mcp/protocol.dart`
- Create: `packages/flutter_qa_mcp/lib/src/mcp/tool.dart`
- Create: `packages/flutter_qa_mcp/test/mcp/protocol_test.dart`

**Context:** Minimal MCP server supporting:
- `initialize` (returns server name/version/capabilities)
- `tools/list` (returns registered tool schemas)
- `tools/call` (invokes a tool by name with arguments, returns result)

Errors follow JSON-RPC 2.0: `{"jsonrpc":"2.0","id":<id>,"error":{"code":-32601,"message":"..."}}`.

- [ ] **Step 1: Define Tool**

```dart
// packages/flutter_qa_mcp/lib/src/mcp/tool.dart
typedef ToolHandler = Future<Map<String, dynamic>> Function(Map<String, dynamic> args);

class Tool {
  Tool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final ToolHandler handler;

  Map<String, dynamic> toDescriptor() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
      };
}
```

- [ ] **Step 2: Write the failing test**

```dart
// packages/flutter_qa_mcp/test/mcp/protocol_test.dart
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/mcp/tool.dart';
import 'package:test/test.dart';

void main() {
  test('initialize returns server info', () async {
    final p = McpProtocol(tools: const []);
    final resp = await p.handle({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'});
    expect(resp['result'], isNotNull);
    expect(resp['result']['serverInfo']['name'], 'flutter_qa_mcp');
  });

  test('tools/list returns registered tools', () async {
    final p = McpProtocol(tools: [
      Tool(
        name: 'echo',
        description: 'echoes input',
        inputSchema: {'type': 'object'},
        handler: (args) async => {'content': [{'type': 'text', 'text': 'ok'}]},
      ),
    ]);
    final resp = await p.handle({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
    expect((resp['result']['tools'] as List).first['name'], 'echo');
  });

  test('tools/call invokes the handler and returns the result', () async {
    final p = McpProtocol(tools: [
      Tool(
        name: 'echo',
        description: '',
        inputSchema: {'type': 'object'},
        handler: (args) async => {'content': [{'type': 'text', 'text': args['msg'] ?? ''}]},
      ),
    ]);
    final resp = await p.handle({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {'name': 'echo', 'arguments': {'msg': 'hi'}},
    });
    expect(resp['result']['content'][0]['text'], 'hi');
  });

  test('unknown method returns -32601', () async {
    final p = McpProtocol(tools: const []);
    final resp = await p.handle({'jsonrpc': '2.0', 'id': 4, 'method': 'nope'});
    expect(resp['error']['code'], -32601);
  });
}
```

- [ ] **Step 3: Implement**

```dart
// packages/flutter_qa_mcp/lib/src/mcp/protocol.dart
import 'tool.dart';
import '../version.dart';

class McpProtocol {
  McpProtocol({required List<Tool> tools}) : _tools = {for (final t in tools) t.name: t};

  final Map<String, Tool> _tools;

  Future<Map<String, dynamic>> handle(Map<String, dynamic> req) async {
    final id = req['id'];
    final method = req['method'] as String?;
    try {
      switch (method) {
        case 'initialize':
          return _ok(id, {
            'protocolVersion': '2025-06-18',
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'flutter_qa_mcp', 'version': packageVersion},
          });
        case 'tools/list':
          return _ok(id, {'tools': _tools.values.map((t) => t.toDescriptor()).toList()});
        case 'tools/call':
          final params = (req['params'] as Map?) ?? const {};
          final name = params['name'] as String?;
          final args = (params['arguments'] as Map?)?.cast<String, dynamic>() ?? const {};
          final tool = name == null ? null : _tools[name];
          if (tool == null) return _err(id, -32602, 'unknown tool: $name');
          final result = await tool.handler(args);
          return _ok(id, result);
        default:
          return _err(id, -32601, 'unknown method: $method');
      }
    } catch (e) {
      return _err(id, -32603, e.toString());
    }
  }

  Map<String, dynamic> _ok(dynamic id, Map<String, dynamic> result) =>
      {'jsonrpc': '2.0', 'id': id, 'result': result};

  Map<String, dynamic> _err(dynamic id, int code, String message) =>
      {'jsonrpc': '2.0', 'id': id, 'error': {'code': code, 'message': message}};
}
```

- [ ] **Step 4: Run tests**

Run: `dart test test/mcp/protocol_test.dart`
Expected: 4 tests passing.

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): JSON-RPC protocol handler (initialize, tools/list, tools/call)"
```

---

## Task 20: VM service client wrapper

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/vm/client.dart`
- Create: `packages/flutter_qa_mcp/test/vm/client_test.dart`

**Context:** Wraps `package:vm_service` to (a) connect to a VM service URI (ws://...), (b) find the Flutter isolate, (c) call a service extension by name with params, (d) reconnect if dropped. v1 keeps reconnection logic out — single connection, fail loudly.

- [ ] **Step 1: Write the failing test**

```dart
// packages/flutter_qa_mcp/test/vm/client_test.dart
import 'package:flutter_qa_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  test('throws ArgumentError for invalid URI scheme', () async {
    expect(
      () => VmClient.connect(Uri.parse('http://localhost:1234')),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Implement (connection logic only; live VM service test happens in Task 24)**

```dart
// packages/flutter_qa_mcp/lib/src/vm/client.dart
import 'dart:convert';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

class VmClient {
  VmClient._(this._service, this._isolateId);

  final VmService _service;
  final String _isolateId;

  static Future<VmClient> connect(Uri uri) async {
    if (uri.scheme != 'ws' && uri.scheme != 'wss') {
      throw ArgumentError('VM service URI must be ws:// or wss://, got: $uri');
    }
    final service = await vmServiceConnectUri(uri.toString());
    final vm = await service.getVM();
    final isolateRef = vm.isolates?.firstWhere(
      (i) => i.id != null,
      orElse: () => throw StateError('no isolates in VM'),
    );
    return VmClient._(service, isolateRef!.id!);
  }

  Future<Map<String, dynamic>> callExtension(String name, [Map<String, dynamic>? args]) async {
    final stringArgs = <String, String>{};
    args?.forEach((k, v) => stringArgs[k] = v is String ? v : jsonEncode(v));
    final response = await _service.callServiceExtension(
      name,
      isolateId: _isolateId,
      args: stringArgs,
    );
    final json = response.json ?? const <String, dynamic>{};
    // Some extensions return their payload as a JSON-encoded string under 'result'.
    if (json['result'] is String) {
      try {
        return jsonDecode(json['result'] as String) as Map<String, dynamic>;
      } catch (_) {
        return json;
      }
    }
    return Map<String, dynamic>.from(json);
  }

  Future<void> dispose() async {
    await _service.dispose();
  }
}
```

- [ ] **Step 3: Run tests**

Run: `dart test test/vm/client_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): VM service client wrapper"
```

---

## Task 21: Wire perception tools into the MCP server

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/tools/perception.dart`
- Modify: `packages/flutter_qa_mcp/bin/flutter_qa_mcp.dart`

- [ ] **Step 1: Implement perception tool factory**

```dart
// packages/flutter_qa_mcp/lib/src/tools/perception.dart
import 'dart:convert';
import '../mcp/tool.dart';
import '../vm/client.dart';

List<Tool> perceptionTools(VmClient vm) => [
      Tool(
        name: 'snapshot',
        description: 'Returns the denoised semantic tree of the currently visible screen.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          final json = await vm.callExtension('ext.qa.snapshot');
          return _toolResult(jsonEncode(json));
        },
      ),
      Tool(
        name: 'inspect',
        description: 'Returns full widget chain and properties for a single element_id.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'element_id': {'type': 'string'},
          },
          'required': ['element_id'],
        },
        handler: (args) async {
          final id = args['element_id'] as String?;
          if (id == null) {
            return _toolError('element_id required');
          }
          final json = await vm.callExtension('ext.qa.inspect', {'element_id': id});
          return _toolResult(jsonEncode(json));
        },
      ),
      Tool(
        name: 'screenshot',
        description: 'Returns a base64-encoded PNG of the current screen.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          final json = await vm.callExtension('ext.qa.screenshot');
          return _toolResult(jsonEncode(json));
        },
      ),
    ];

Map<String, dynamic> _toolResult(String text) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
    };

Map<String, dynamic> _toolError(String message) => {
      'isError': true,
      'content': [
        {'type': 'text', 'text': message},
      ],
    };
```

- [ ] **Step 2: Replace CLI entry's "not yet implemented" with the full runtime**

```dart
// packages/flutter_qa_mcp/bin/flutter_qa_mcp.dart (replace existing)
import 'dart:io';
import 'package:args/args.dart';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/mcp/transport.dart';
import 'package:flutter_qa_mcp/src/tools/perception.dart';
import 'package:flutter_qa_mcp/src/version.dart';
import 'package:flutter_qa_mcp/src/vm/client.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('attach', help: 'VM service URI (ws://...)')
    ..addFlag('version', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }
  if (parsed['version'] as bool) {
    stdout.writeln(packageVersion);
    return;
  }
  final attach = parsed['attach'] as String?;
  if (attach == null) {
    stderr.writeln('--attach <vm-service-uri> is required');
    exit(64);
  }

  final vm = await VmClient.connect(Uri.parse(attach));
  final transport = StdioTransport(input: stdin, output: stdout);
  final protocol = McpProtocol(tools: perceptionTools(vm));

  await for (final msg in transport.incoming) {
    final resp = await protocol.handle(msg);
    transport.send(resp);
  }
}
```

- [ ] **Step 3: Smoke-run the CLI**

```bash
cd packages/flutter_qa_mcp && dart run bin/flutter_qa_mcp.dart --help
```
Expected: prints usage including `--attach`.

- [ ] **Step 4: Commit**

```bash
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): wire snapshot/inspect/screenshot tools end-to-end"
```

---

## Task 22: Demo Flutter app for integration testing

**Files:**
- Create: `examples/demo_app/pubspec.yaml`
- Create: `examples/demo_app/lib/main.dart`

- [ ] **Step 1: Create demo app**

```bash
cd examples && flutter create --org dev.flutterqa --project-name demo_app demo_app
```

- [ ] **Step 2: Replace demo_app/lib/main.dart**

```dart
// examples/demo_app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/flutter_qa_probe.dart';

void main() {
  FlutterQAProbe.install();
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Demo',
      navigatorObservers: [FlutterQAProbe.routeTracker],
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/cart': (_) => const CartScreen(),
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Welcome'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/cart'),
              child: const Text('Go to cart'),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.shopping_cart),
            ),
          ],
        ),
      ),
    );
  }
}

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Item A'),
            trailing: GestureDetector(
              onTap: () {},
              child: const Icon(Icons.delete),
            ),
          ),
          ListTile(
            title: const Text('Item B'),
            trailing: GestureDetector(
              onTap: () {},
              child: const Icon(Icons.delete),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Add `flutter_qa_probe` path dependency**

```yaml
# examples/demo_app/pubspec.yaml (add to dependencies)
dependencies:
  flutter:
    sdk: flutter
  flutter_qa_probe:
    path: ../../packages/flutter_qa_probe
```

- [ ] **Step 4: Run melos bootstrap**

```bash
cd ../.. && melos bootstrap
```

- [ ] **Step 5: Sanity-run the app**

```bash
cd examples/demo_app && flutter run -d <device_or_simulator>
```
Expected: app launches; tapping "Go to cart" navigates; back arrow returns.

(If a simulator/device isn't available in the engineer's environment, skip the launch and rely on the integration test in Task 23.)

- [ ] **Step 6: Commit**

```bash
git add examples/demo_app/
git commit -m "test: demo Flutter app exercising probe wiring"
```

---

## Task 23: Integration test — boot demo app, attach MCP, call snapshot

**Files:**
- Create: `examples/demo_app/integration_test/qa_smoke_test.dart`
- Create: `packages/flutter_qa_mcp/test/e2e/snapshot_e2e_test.dart`

**Context:** End-to-end test using `flutter_test`'s integration_test harness to boot the demo app under a VM service URI, then spawn the MCP server in-process and call `tools/call` for `snapshot`. Avoids needing a real simulator.

- [ ] **Step 1: Create integration test entry**

```dart
// examples/demo_app/integration_test/qa_smoke_test.dart
import 'package:demo_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home renders and contains "Go to cart"', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.text('Go to cart'), findsOneWidget);
    // Pause long enough for an attaching VM service client to call snapshot.
    await tester.pump(const Duration(seconds: 30));
  });
}
```

Add `integration_test` to demo_app dev deps:
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
```

- [ ] **Step 2: Create the E2E test driver**

```dart
// packages/flutter_qa_mcp/test/e2e/snapshot_e2e_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/tools/perception.dart';
import 'package:flutter_qa_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  late Process flutter;
  late Uri vmUri;

  setUpAll(() async {
    flutter = await Process.start(
      'flutter',
      ['test', 'integration_test/qa_smoke_test.dart', '--machine'],
      workingDirectory: '../../examples/demo_app',
    );
    // Read JSON-encoded progress lines until we see an "observatoryUri" event.
    final completer = Completer<Uri>();
    flutter.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final m = _tryParse(line);
      final uri = m?['params']?['observatoryUri'] as String?;
      if (uri != null && !completer.isCompleted) completer.complete(Uri.parse(uri));
    });
    vmUri = await completer.future.timeout(const Duration(seconds: 60));
  });

  tearDownAll(() async {
    flutter.kill();
    await flutter.exitCode;
  });

  test('snapshot tool returns elements from demo app home screen', () async {
    final vm = await VmClient.connect(vmUri);
    final protocol = McpProtocol(tools: perceptionTools(vm));
    final resp = await protocol.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': 'snapshot', 'arguments': {}},
    });
    final text = ((resp['result'] as Map)['content'] as List).first['text'] as String;
    final snap = jsonDecode(text) as Map<String, dynamic>;
    final elements = snap['elements'] as List;
    expect(elements, isNotEmpty);
    expect(
      elements.any((e) => (e as Map)['label'] == 'Go to cart'),
      isTrue,
      reason: 'expected the home-screen button label to appear',
    );
    await vm.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Map<String, dynamic>? _tryParse(String line) {
  try {
    final v = jsonDecode(line);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}
```

- [ ] **Step 3: Run the E2E test**

```bash
cd packages/flutter_qa_mcp && dart test test/e2e/snapshot_e2e_test.dart
```
Expected: PASS. The test boots demo_app under `flutter test --machine`, attaches a VM client, calls `snapshot`, and finds the "Go to cart" label.

If the test infra (flutter on PATH, simulator/device for integration_test) isn't available, mark this test as `@Tags(['e2e'])` and document running it manually. The unit tests above already cover the moving pieces.

- [ ] **Step 4: Commit**

```bash
git add examples/demo_app/integration_test/ packages/flutter_qa_mcp/test/e2e/
git commit -m "test(e2e): MCP snapshot against running demo app"
```

---

## Task 24: Package READMEs and quickstart

**Files:**
- Create: `packages/flutter_qa_probe/README.md`
- Create: `packages/flutter_qa_mcp/README.md`
- Create: `README.md` (root)

- [ ] **Step 1: Probe README**

```markdown
# flutter_qa_probe

Runtime probe that exposes a Flutter app's widget tree to QA agents via the Dart VM service.

## Install

```yaml
dev_dependencies:
  flutter_qa_probe:
    path: ../packages/flutter_qa_probe   # or git: / hosted: when published
```

## Use

```dart
import 'package:flutter_qa_probe/flutter_qa_probe.dart';

void main() {
  FlutterQAProbe.install();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [FlutterQAProbe.routeTracker],
      // ...
    );
  }
}
```

`install()` is a no-op in release builds. Requires `--track-widget-creation` (default in debug and profile mode under `flutter run`).

## Exposed VM service extensions

- `ext.qa.ping` — health check
- `ext.qa.snapshot` — denoised semantic tree
- `ext.qa.inspect` — full widget chain for one element_id
- `ext.qa.screenshot` — base64 PNG of the current frame
```

- [ ] **Step 2: MCP README**

```markdown
# flutter_qa_mcp

MCP server that bridges an LLM agent to a running Flutter app via the Dart VM service.

## Run

```bash
# Terminal 1: start the app
flutter run

# Terminal 2: start the MCP server (paste the VM Service URI printed by `flutter run`)
dart run flutter_qa_mcp --attach ws://127.0.0.1:54321/abc=/ws
```

Configure your MCP client to point at the running server over stdio.

## Tools (v1)

- `snapshot` — denoised semantic tree of the visible screen
- `inspect(element_id)` — full widget chain for one element
- `screenshot` — base64 PNG of the current frame
```

- [ ] **Step 3: Root README**

```markdown
# ai_mobile_eyes — Flutter QA MCP

A runtime SDK + MCP server that lets LLM agents perceive and (eventually) drive Flutter apps for QA.

## Status

- **Plan 1 (Perception):** in progress — see `docs/superpowers/plans/2026-05-21-flutter-qa-mcp-plan-1-perception.md`
- **Plan 2 (Drive):** not started
- **Plan 3 (Augmentation):** not started

## Layout

- `packages/flutter_qa_probe/` — Dart Flutter package, added as a dev dep in the app under test
- `packages/flutter_qa_mcp/` — Standalone MCP server
- `examples/demo_app/` — Tiny Flutter app for integration tests
- `docs/superpowers/specs/` — Design specs
- `docs/superpowers/plans/` — Implementation plans
```

- [ ] **Step 4: Commit**

```bash
git add README.md packages/*/README.md
git commit -m "docs: package READMEs and root quickstart"
```

---

## Done state

After all tasks land:

- `flutter run` (with the probe installed) prints a VM service URI.
- `dart run flutter_qa_mcp --attach <uri>` connects and serves MCP over stdio.
- An MCP client can call `snapshot`, `inspect`, `screenshot` and get well-typed JSON responses backed by the real running app.
- `dart test` and `flutter test` both pass across both packages.
- One E2E integration test boots demo_app and validates `snapshot` end-to-end.

Plan 2 (actions, sync tools) and Plan 3 (memory, dashboard, VLM proposals) build on this foundation. Both will be written as separate plans against the same spec.
