# Flutter QA MCP — Plan 3: Augmentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Close the loop. The agent's snapshots now include an `unresolved[]` array of tappable regions with no confident label, each carrying label proposals (from source-location AST and optionally VLM). A persistent per-project semantic map turns human curation into compounding agent vocabulary. A bundled web dashboard at `localhost:7345` lets a human review and confirm proposals in under 30 seconds per element.

**Architecture:** All proposal generation moves to the MCP server (host-side), where AST parsing is natural. The probe stays minimal: it emits raw element data plus `creation_location`. The MCP server:
- Resolves `creation_location` → enclosing function name via `AstParser` (relocated from the probe package).
- Loads `.flutter_qa/map.json` and applies persistent labels.
- Writes new labels back when `label_element` is called.
- Serves the review dashboard from the same process when `flutter-qa-mcp review` is invoked.

**Tech Stack (deltas from Plan 2):**
- `package:shelf` + `package:shelf_router` (HTTP server for dashboard)
- `package:analyzer` — moves from `flutter_qa_probe` dev_deps to `flutter_qa_mcp` regular deps
- Static dashboard: vanilla HTML/CSS/JS shipped as Dart string constants or asset files

**Repo layout changes:**

```
packages/flutter_qa_probe/
  lib/src/source/ast_parser.dart         (REMOVED — moved to mcp)
  test/source/                            (REMOVED)
  pubspec.yaml                            (analyzer, path removed)

packages/flutter_qa_mcp/
  pubspec.yaml                            (analyzer, path, shelf, shelf_router added)
  lib/src/
    source/ast_parser.dart                (NEW — moved from probe)
    map/
      semantic_map.dart                   (NEW — load/save .flutter_qa/map.json)
      map_record.dart                     (NEW — JSON shape)
    enrich/
      snapshot_enricher.dart              (NEW — adds proposals + applies persistent labels)
      sourceloc_proposer.dart             (NEW — uses AstParser)
      som_annotator.dart                  (NEW — Set-of-Mark overlay on screenshots)
    tools/
      memory_tools.dart                   (NEW — label_element, get_labels, recall)
    dashboard/
      server.dart                         (NEW — shelf HTTP server)
      handlers.dart                       (NEW — API routes)
      static/                             (NEW — index.html, main.js, style.css)
  bin/flutter_qa_mcp.dart                 (extended with `review` subcommand)
  test/                                   (new tests for each module)
```

**Out of scope (Plan 4 / future):**
- Conflict resolution UI when two devs label the same fingerprint differently
- VLM proposal *generation* is the agent's job (call `screenshot(annotated=true)` then ask the VLM and call `label_element` with `source=vlm`). Plan 3 supports this flow but doesn't bundle a VLM client.
- Network and state_diff proposal sources (deferred per spec).
- Map storage in SQLite if size grows past ~5k entries.

---

## Task 1: Move AstParser from probe to MCP package

**Files:**
- Delete: `packages/flutter_qa_probe/lib/src/source/ast_parser.dart`
- Delete: `packages/flutter_qa_probe/test/source/ast_parser_test.dart`
- Delete: `packages/flutter_qa_probe/test/fixtures/sample_widget_file.dart`
- Modify: `packages/flutter_qa_probe/pubspec.yaml` (remove analyzer, path)
- Modify: `packages/flutter_qa_probe/analysis_options.yaml` (remove fixtures exclude)
- Create: `packages/flutter_qa_mcp/lib/src/source/ast_parser.dart` (same content)
- Create: `packages/flutter_qa_mcp/test/source/ast_parser_test.dart` (same content; path relative to mcp package)
- Create: `packages/flutter_qa_mcp/test/fixtures/sample_widget_file.dart` (same)
- Modify: `packages/flutter_qa_mcp/pubspec.yaml` (add `analyzer: ^6.4.0`, `path: ^1.9.0`)

- [ ] **Step 1: Move files via git mv**

```bash
cd /Users/mohn93/Desktop/side_projects/ai_mobile_eyes
mkdir -p packages/flutter_qa_mcp/lib/src/source
mkdir -p packages/flutter_qa_mcp/test/source
mkdir -p packages/flutter_qa_mcp/test/fixtures
git mv packages/flutter_qa_probe/lib/src/source/ast_parser.dart \
       packages/flutter_qa_mcp/lib/src/source/ast_parser.dart
git mv packages/flutter_qa_probe/test/source/ast_parser_test.dart \
       packages/flutter_qa_mcp/test/source/ast_parser_test.dart
git mv packages/flutter_qa_probe/test/fixtures/sample_widget_file.dart \
       packages/flutter_qa_mcp/test/fixtures/sample_widget_file.dart
# Remove the now-empty fixtures dir from probe
rmdir packages/flutter_qa_probe/test/source packages/flutter_qa_probe/test/fixtures 2>/dev/null || true
```

- [ ] **Step 2: Remove `analyzer` / `path` from probe pubspec**

In `packages/flutter_qa_probe/pubspec.yaml`, delete the two lines under `dev_dependencies:`:
```yaml
  analyzer: ^6.4.0
  path: ^1.9.0
```

- [ ] **Step 3: Drop the analysis_options exclude**

In `packages/flutter_qa_probe/analysis_options.yaml`, remove the `test/fixtures/**` exclude line. If the file becomes empty, delete it.

- [ ] **Step 4: Add analyzer to MCP pubspec**

In `packages/flutter_qa_mcp/pubspec.yaml` under `dependencies:`:
```yaml
  analyzer: ^6.4.0
  path: ^1.9.0
```

- [ ] **Step 5: Create analysis_options.yaml for MCP package to exclude fixtures**

```yaml
# packages/flutter_qa_mcp/analysis_options.yaml
include: package:lints/recommended.yaml
analyzer:
  exclude:
    - test/fixtures/**
```

- [ ] **Step 6: Bootstrap and verify**

```bash
melos bootstrap
cd packages/flutter_qa_probe && flutter test && flutter analyze
cd ../flutter_qa_mcp && dart test && dart analyze
```

All tests pass. Both packages analyze clean.

- [ ] **Step 7: Commit**

```
git add -A
git commit -m "refactor: move AstParser from probe to mcp package"
```

---

## Task 2: ElementRecord supports proposals[]

**Files:**
- Modify: `packages/flutter_qa_probe/lib/src/tree/element_record.dart`
- Modify: `packages/flutter_qa_probe/test/tree/snapshot_builder_test.dart`

**Context:** Plan 1's `ElementRecord` has `label`, `labelSource`, `bounds`, etc. We extend it with an optional `proposals` field used when the element is unresolved. The `SnapshotRecord` toJson stays the same shape but now also emits an `unresolved` key.

- [ ] **Step 1: Update ElementRecord**

Edit `packages/flutter_qa_probe/lib/src/tree/element_record.dart`:

Add a `Proposal` class:
```dart
class Proposal {
  Proposal({required this.source, required this.label, required this.confidence});
  final String source;
  final String label;
  final double confidence;
  Map<String, dynamic> toJson() => {
        'source': source,
        'label': label,
        'confidence': confidence,
      };
}
```

Add a `proposals` field to `ElementRecord`:
```dart
final List<Proposal> proposals;
```

Update constructor and `toJson` to include `proposals` only when non-empty:
```dart
if (proposals.isNotEmpty) 'proposals': proposals.map((p) => p.toJson()).toList(),
```

Default `proposals` to `const []` in the constructor.

- [ ] **Step 2: Update SnapshotRecord toJson to include `unresolved`**

The probe-side SnapshotRecord still doesn't *generate* unresolved (that happens MCP-side), but the schema needs an `unresolved` slot that defaults to an empty list:

```dart
class SnapshotRecord {
  SnapshotRecord({
    required this.route,
    required this.viewport,
    required this.elements,
    this.unresolved = const <ElementRecord>[],
  });
  // ...
  final List<ElementRecord> unresolved;

  Map<String, dynamic> toJson() => {
        if (route != null) 'route': route,
        'viewport': {'w': viewport.width, 'h': viewport.height},
        'elements': elements.map((e) => e.toJson()).toList(),
        'unresolved': unresolved.map((e) => e.toJson()).toList(),
      };
}
```

- [ ] **Step 3: Verify existing tests still pass**

```bash
cd packages/flutter_qa_probe && flutter test && flutter analyze
```

The existing snapshot_builder_test should still pass because:
- New required field has a default of `const []`
- `toJson` now emits `unresolved: []` for tests that snapshot-build directly. Existing tests don't check the absence of this key.

- [ ] **Step 4: Commit**

```
git add packages/flutter_qa_probe/
git commit -m "feat(probe): ElementRecord.proposals[] + SnapshotRecord.unresolved[]"
```

---

## Task 3: SnapshotBuilder splits resolved vs unresolved

**Files:**
- Modify: `packages/flutter_qa_probe/lib/src/tree/snapshot_builder.dart`
- Create: `packages/flutter_qa_probe/test/tree/snapshot_builder_unresolved_test.dart`

**Context:** Promoted elements with no inferred label (and no icon role) are demoted to `unresolved[]` instead of being dropped. Their bounds and creation_location are preserved so MCP-side enrichers can add proposals.

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_probe/test/tree/snapshot_builder_unresolved_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/tree/snapshot_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GestureDetector with no text or icon lands in unresolved[]', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          onTap: () {},
          child: const SizedBox(width: 50, height: 50, child: ColoredBox(color: Color(0xFF000000))),
        ),
      ),
    ));

    final snap = SnapshotBuilder.build();
    final unresolvedGD = snap.unresolved.where((e) => e.widgetType == 'GestureDetector');
    expect(unresolvedGD, isNotEmpty);
    // It should NOT be in elements[] (because it has no label)
    final resolvedGD = snap.elements.where((e) => e.widgetType == 'GestureDetector' && e.label != null);
    expect(resolvedGD, isEmpty);
  });

  testWidgets('button with a Text label stays in elements[], not unresolved', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ElevatedButton(onPressed: () {}, child: const Text('Go'))),
    ));
    final snap = SnapshotBuilder.build();
    expect(snap.elements.any((e) => e.label == 'Go'), isTrue);
    expect(snap.unresolved.any((e) => e.label == 'Go'), isFalse);
  });
}
```

- [ ] **Step 2: Update SnapshotBuilder logic**

In `packages/flutter_qa_probe/lib/src/tree/snapshot_builder.dart`, after computing each `ElementRecord`, branch on `inferred.label`:
- If `inferred.label != null`: add to `elements[]` (resolved).
- If `inferred.label == null`: build the record with `label: null` and add to `unresolved[]`.

Both branches use the same fingerprint, creation_location, bounds. Element IDs continue to be `e_${index}` based on the *combined* counter so an MCP-side resolver can still find them. Use a single counter incremented across both lists.

Sketch:
```dart
final elements = <ElementRecord>[];
final unresolved = <ElementRecord>[];
var counter = 0;

for (final node in raw) {
  // ... existing filter/promote logic ...
  final inferred = RoleInference.infer(node.element);
  final record = ElementRecord(
    id: 'e_$counter',
    // ... same as before ...
    label: inferred.label,
    labelSource: inferred.labelSource.name,
    proposals: const [],
  );
  if (inferred.label != null) {
    elements.add(record);
  } else {
    unresolved.add(record);
  }
  counter++;
}

return SnapshotRecord(
  route: FlutterQAProbe.routeTracker.currentRoute,
  viewport: media.size,
  elements: elements,
  unresolved: unresolved,
);
```

- [ ] **Step 3: Update ElementResolver to consider both lists**

Edit `packages/flutter_qa_probe/lib/src/resolver/element_resolver.dart`: since `unresolved` elements now also have valid `e_N` ids, the resolver should still find them by walking the same filter sequence used by SnapshotBuilder. The current implementation already walks promote+bounds without consulting "has label" — so it should be correct as-is. Verify by reading the existing code; if it filters on label, fix that.

- [ ] **Step 4: Run all tests + analyze**

```bash
cd packages/flutter_qa_probe && flutter test && flutter analyze
```

Existing tests should still pass — the resolved button still appears in `elements[]`, and `unresolved[]` is just a new bucket. The new test verifies the bucketing.

- [ ] **Step 5: Commit**

```
git add packages/flutter_qa_probe/
git commit -m "feat(probe): split snapshot into elements (resolved) vs unresolved"
```

---

## Task 4: Semantic map storage (load/save .flutter_qa/map.json)

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/map/map_record.dart`
- Create: `packages/flutter_qa_mcp/lib/src/map/semantic_map.dart`
- Create: `packages/flutter_qa_mcp/test/map/semantic_map_test.dart`

**Context:** Stores per-fingerprint labels in JSON. Lives at `<project_root>/.flutter_qa/map.json`. Loaded lazily, written atomically (write to temp + rename).

- [ ] **Step 1: Define record shape**

```dart
// packages/flutter_qa_mcp/lib/src/map/map_record.dart
class MapEntry {
  MapEntry({
    required this.fingerprint,
    this.humanLabel,
    this.creationLocation,
    this.screenContext,
    this.observationCount = 0,
    this.proposals = const [],
    this.dismissed = false,
  });

  final String fingerprint;
  String? humanLabel;
  String? creationLocation;
  String? screenContext;
  int observationCount;
  bool dismissed;
  List<ProposalRecord> proposals;

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        if (humanLabel != null) 'human_label': humanLabel,
        if (creationLocation != null) 'creation_location': creationLocation,
        if (screenContext != null) 'screen_context': screenContext,
        'observation_count': observationCount,
        if (dismissed) 'dismissed': true,
        if (proposals.isNotEmpty) 'proposals': proposals.map((p) => p.toJson()).toList(),
      };

  static MapEntry fromJson(Map<String, dynamic> json) => MapEntry(
        fingerprint: json['fingerprint'] as String,
        humanLabel: json['human_label'] as String?,
        creationLocation: json['creation_location'] as String?,
        screenContext: json['screen_context'] as String?,
        observationCount: (json['observation_count'] as num?)?.toInt() ?? 0,
        dismissed: json['dismissed'] as bool? ?? false,
        proposals: (json['proposals'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(ProposalRecord.fromJson)
                .toList() ??
            [],
      );
}

class ProposalRecord {
  ProposalRecord({
    required this.source,
    required this.label,
    required this.confidence,
    required this.firstSeen,
  });

  final String source;
  final String label;
  final double confidence;
  final DateTime firstSeen;

  Map<String, dynamic> toJson() => {
        'source': source,
        'label': label,
        'confidence': confidence,
        'first_seen': firstSeen.toIso8601String(),
      };

  static ProposalRecord fromJson(Map<String, dynamic> json) => ProposalRecord(
        source: json['source'] as String,
        label: json['label'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        firstSeen: DateTime.parse(json['first_seen'] as String),
      );
}
```

- [ ] **Step 2: Failing test**

```dart
// packages/flutter_qa_mcp/test/map/semantic_map_test.dart
import 'dart:io';
import 'package:flutter_qa_mcp/src/map/map_record.dart';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('flutter_qa_map_test_');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('save then load round-trips entries', () async {
    final map = SemanticMap(projectRoot: tmp.path);
    map.upsert(MapEntry(
      fingerprint: 'f_abc123',
      humanLabel: 'Checkout',
      observationCount: 7,
    ));
    await map.save();

    final fresh = SemanticMap(projectRoot: tmp.path);
    await fresh.load();
    final entry = fresh.get('f_abc123');
    expect(entry, isNotNull);
    expect(entry!.humanLabel, 'Checkout');
    expect(entry.observationCount, 7);
  });

  test('load on missing file is a no-op', () async {
    final map = SemanticMap(projectRoot: tmp.path);
    await map.load();
    expect(map.entries, isEmpty);
  });

  test('save creates .flutter_qa/map.json with parents as needed', () async {
    final map = SemanticMap(projectRoot: tmp.path);
    map.upsert(MapEntry(fingerprint: 'f_x'));
    await map.save();
    expect(File('${tmp.path}/.flutter_qa/map.json').existsSync(), isTrue);
  });
}
```

- [ ] **Step 3: Implement**

```dart
// packages/flutter_qa_mcp/lib/src/map/semantic_map.dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'map_record.dart';

class SemanticMap {
  SemanticMap({required this.projectRoot});
  final String projectRoot;
  final Map<String, MapEntry> _entries = {};

  Iterable<MapEntry> get entries => _entries.values;

  MapEntry? get(String fingerprint) => _entries[fingerprint];

  void upsert(MapEntry entry) {
    _entries[entry.fingerprint] = entry;
  }

  void delete(String fingerprint) {
    _entries.remove(fingerprint);
  }

  String get _filePath => p.join(projectRoot, '.flutter_qa', 'map.json');

  Future<void> load() async {
    final file = File(_filePath);
    if (!file.existsSync()) return;
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final list = (raw['entries'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(MapEntry.fromJson);
    _entries.clear();
    for (final e in list) {
      _entries[e.fingerprint] = e;
    }
  }

  Future<void> save() async {
    final dir = Directory(p.dirname(_filePath));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final body = {
      'version': 1,
      'entries': _entries.values.map((e) => e.toJson()).toList(),
    };
    final tmp = File('${_filePath}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(body));
    await tmp.rename(_filePath);
  }
}
```

- [ ] **Step 4: Run tests + analyze**

```bash
cd packages/flutter_qa_mcp && dart test test/map/semantic_map_test.dart && dart analyze
```

- [ ] **Step 5: Commit**

```
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): persistent semantic map (.flutter_qa/map.json)"
```

---

## Task 5: Source-location proposer (uses AstParser)

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/enrich/sourceloc_proposer.dart`
- Create: `packages/flutter_qa_mcp/test/enrich/sourceloc_proposer_test.dart`

**Context:** Given a `creation_location` string like `lib/cart_screen.dart:127:14`, parse the file with `AstParser.enclosingFunction` and return a label proposal (e.g., `_buildRemoveButton` → "Remove").

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_mcp/test/enrich/sourceloc_proposer_test.dart
import 'package:flutter_qa_mcp/src/enrich/sourceloc_proposer.dart';
import 'package:test/test.dart';

void main() {
  test('returns proposal from enclosing function name', () {
    // Uses the same fixture path the AstParser test uses (test/fixtures/sample_widget_file.dart).
    final proposal = SourceLocProposer.propose(
      creationLocation: 'test/fixtures/sample_widget_file.dart:5:12',
    );
    expect(proposal, isNotNull);
    expect(proposal!.source, 'source_location');
    expect(proposal.label, contains('Remove'));  // _buildRemoveButton → "Remove" or "_buildRemoveButton"
    expect(proposal.confidence, greaterThan(0));
    expect(proposal.confidence, lessThanOrEqualTo(1));
  });

  test('returns null when creation_location is malformed', () {
    expect(SourceLocProposer.propose(creationLocation: 'no-colons-here'), isNull);
    expect(SourceLocProposer.propose(creationLocation: null), isNull);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_mcp/lib/src/enrich/sourceloc_proposer.dart
import '../map/map_record.dart';
import '../source/ast_parser.dart';

class SourceLocProposer {
  /// Parses `creationLocation` (format "file:line:column") and returns a label
  /// proposal derived from the enclosing function/method name.
  static ProposalRecord? propose({required String? creationLocation}) {
    if (creationLocation == null) return null;
    final parts = creationLocation.split(':');
    if (parts.length < 3) return null;
    final column = int.tryParse(parts.last);
    final line = int.tryParse(parts[parts.length - 2]);
    final file = parts.take(parts.length - 2).join(':');
    if (column == null || line == null || file.isEmpty) return null;

    final fn = AstParser.enclosingFunction(filePath: file, line: line, column: column);
    if (fn == null) return null;

    return ProposalRecord(
      source: 'source_location',
      label: _humanize(fn),
      confidence: 0.7,
      firstSeen: DateTime.now(),
    );
  }

  /// Converts a Dart identifier (e.g. `_buildRemoveButton`, `onCheckoutPressed`)
  /// into a space-separated label ("Remove Button" / "Checkout Pressed").
  static String _humanize(String identifier) {
    var name = identifier.startsWith('_') ? identifier.substring(1) : identifier;
    // Drop common prefixes
    for (final prefix in ['build', 'on', '_on', '_build']) {
      if (name.toLowerCase().startsWith(prefix.toLowerCase()) && name.length > prefix.length) {
        name = name.substring(prefix.length);
        break;
      }
    }
    // Split camelCase
    final words = name.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
    return words.isEmpty ? identifier : words;
  }
}
```

- [ ] **Step 3: Run tests + analyze**

- [ ] **Step 4: Commit**

```
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): source-location label proposer using AstParser"
```

---

## Task 6: Snapshot enricher (applies proposals + persistent labels)

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/enrich/snapshot_enricher.dart`
- Create: `packages/flutter_qa_mcp/test/enrich/snapshot_enricher_test.dart`

**Context:** Takes the raw probe-emitted snapshot JSON and the `SemanticMap`, and returns an enriched snapshot:
- For each `unresolved` element, attaches `source_location` proposals.
- For each `elements` and `unresolved` element, if its fingerprint has a `human_label` in the map, promotes it from `unresolved` → `elements` with that label.

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_mcp/test/enrich/snapshot_enricher_test.dart
import 'package:flutter_qa_mcp/src/enrich/snapshot_enricher.dart';
import 'package:flutter_qa_mcp/src/map/map_record.dart';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:test/test.dart';

void main() {
  test('unresolved gains source_location proposal when creation_location parseable', () {
    final raw = {
      'route': '/cart',
      'viewport': {'w': 400, 'h': 800},
      'elements': [],
      'unresolved': [
        {
          'id': 'e_0',
          'fingerprint': 'f_x',
          'widget_type': 'GestureDetector',
          'role': 'tappable',
          'label_source': 'none',
          'creation_location': 'test/fixtures/sample_widget_file.dart:5:12',
          'enabled': true,
        }
      ],
    };
    final map = SemanticMap(projectRoot: '.');  // not loaded — irrelevant for this test
    final enriched = SnapshotEnricher.enrich(raw: raw, map: map);
    final unresolved = enriched['unresolved'] as List;
    expect(unresolved, hasLength(1));
    final proposals = (unresolved.first as Map)['proposals'] as List;
    expect(proposals, isNotEmpty);
    expect((proposals.first as Map)['source'], 'source_location');
  });

  test('human_label promotes an unresolved element to resolved', () {
    final raw = {
      'route': '/cart',
      'viewport': {'w': 400, 'h': 800},
      'elements': [],
      'unresolved': [
        {
          'id': 'e_0',
          'fingerprint': 'f_y',
          'widget_type': 'GestureDetector',
          'role': 'tappable',
          'label_source': 'none',
          'enabled': true,
        }
      ],
    };
    final map = SemanticMap(projectRoot: '.');
    map.upsert(MapEntry(fingerprint: 'f_y', humanLabel: 'Remove Item'));
    final enriched = SnapshotEnricher.enrich(raw: raw, map: map);
    expect((enriched['unresolved'] as List), isEmpty);
    final elements = enriched['elements'] as List;
    expect(elements, hasLength(1));
    expect((elements.first as Map)['label'], 'Remove Item');
    expect((elements.first as Map)['label_source'], 'human');
  });
}
```

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_mcp/lib/src/enrich/snapshot_enricher.dart
import '../map/semantic_map.dart';
import 'sourceloc_proposer.dart';

class SnapshotEnricher {
  static Map<String, dynamic> enrich({
    required Map<String, dynamic> raw,
    required SemanticMap map,
  }) {
    final elements = <Map<String, dynamic>>[
      ...((raw['elements'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e)),
    ];
    final unresolved = <Map<String, dynamic>>[];

    for (final element in ((raw['unresolved'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))) {
      final fp = element['fingerprint'] as String?;
      final mapped = fp == null ? null : map.get(fp);

      if (mapped?.humanLabel != null) {
        element['label'] = mapped!.humanLabel;
        element['label_source'] = 'human';
        elements.add(element);
        continue;
      }

      // Otherwise, generate proposals.
      final proposals = <Map<String, dynamic>>[];
      final loc = element['creation_location'] as String?;
      final srcProp = SourceLocProposer.propose(creationLocation: loc);
      if (srcProp != null) {
        proposals.add(srcProp.toJson());
      }
      // Include any persisted proposals from the map (e.g., from vlm calls).
      if (mapped != null) {
        for (final p in mapped.proposals) {
          proposals.add(p.toJson());
        }
      }
      if (proposals.isNotEmpty) {
        element['proposals'] = proposals;
      }
      unresolved.add(element);
    }

    // Apply human_label promotion to already-resolved elements too (rename + label_source).
    for (final el in elements) {
      final fp = el['fingerprint'] as String?;
      final mapped = fp == null ? null : map.get(fp);
      if (mapped?.humanLabel != null) {
        el['label'] = mapped!.humanLabel;
        el['label_source'] = 'human';
      }
    }

    return {
      ...raw,
      'elements': elements,
      'unresolved': unresolved,
    };
  }
}
```

- [ ] **Step 3: Run tests + analyze**

- [ ] **Step 4: Commit**

```
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): snapshot enricher applying proposals + persistent labels"
```

---

## Task 7: Memory tools (label_element, get_labels, recall)

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/tools/memory_tools.dart`
- Create: `packages/flutter_qa_mcp/test/tools/memory_tools_test.dart`

**Context:** Three MCP tools that read/write the SemanticMap. They don't call any probe extension — they're pure MCP-side.

- [ ] **Step 1: Failing test**

```dart
// packages/flutter_qa_mcp/test/tools/memory_tools_test.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:flutter_qa_mcp/src/tools/memory_tools.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late SemanticMap map;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('memory_tools_test_');
    map = SemanticMap(projectRoot: tmp.path);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) async {
    final tool = memoryTools(map).firstWhere((t) => t.name == name);
    final result = await tool.handler(args);
    final text = ((result['content'] as List).first as Map)['text'] as String;
    return jsonDecode(text) as Map<String, dynamic>;
  }

  test('label_element writes a human label and persists to disk', () async {
    final resp = await call('label_element', {
      'fingerprint': 'f_abc',
      'name': 'Checkout',
    });
    expect(resp['success'], isTrue);
    expect(map.get('f_abc')?.humanLabel, 'Checkout');
    expect(File('${tmp.path}/.flutter_qa/map.json').existsSync(), isTrue);
  });

  test('get_labels returns all human-labeled entries', () async {
    map.upsert(MapEntry(fingerprint: 'f_1', humanLabel: 'A'));
    map.upsert(MapEntry(fingerprint: 'f_2', humanLabel: 'B'));
    final resp = await call('get_labels', {});
    final labels = resp['labels'] as List;
    expect(labels, hasLength(2));
  });

  test('recall does a case-insensitive substring search on human_label', () async {
    map.upsert(MapEntry(fingerprint: 'f_1', humanLabel: 'Checkout Button'));
    map.upsert(MapEntry(fingerprint: 'f_2', humanLabel: 'Profile Avatar'));
    final resp = await call('recall', {'query': 'check'});
    final matches = resp['matches'] as List;
    expect(matches, hasLength(1));
    expect((matches.first as Map)['human_label'], 'Checkout Button');
  });
}
```

Note: `memoryTools(SemanticMap)` is the factory. It takes a map instance rather than a VmClient because these tools are pure MCP-side.

- [ ] **Step 2: Implement**

```dart
// packages/flutter_qa_mcp/lib/src/tools/memory_tools.dart
import 'dart:convert';
import '../map/map_record.dart';
import '../map/semantic_map.dart';
import '../mcp/tool.dart';

List<Tool> memoryTools(SemanticMap map) => [
      Tool(
        name: 'label_element',
        description: 'Persists a human label for an element fingerprint. Subsequent snapshots will use this label.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'fingerprint': {'type': 'string'},
            'name': {'type': 'string'},
            'notes': {'type': 'string'},
          },
          'required': ['fingerprint', 'name'],
        },
        handler: (args) async {
          final fp = args['fingerprint'] as String?;
          final name = args['name'] as String?;
          if (fp == null || name == null) {
            return _result(jsonEncode({'success': false, 'error': 'fingerprint and name required'}));
          }
          final existing = map.get(fp);
          if (existing == null) {
            map.upsert(MapEntry(
              fingerprint: fp,
              humanLabel: name,
              observationCount: 1,
            ));
          } else {
            existing.humanLabel = name;
            existing.observationCount += 1;
          }
          await map.save();
          return _result(jsonEncode({'success': true, 'fingerprint': fp, 'label': name}));
        },
      ),
      Tool(
        name: 'get_labels',
        description: 'Returns all persistent labels (entries with human_label set).',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (args) async {
          final labels = map.entries
              .where((e) => e.humanLabel != null)
              .map((e) => e.toJson())
              .toList();
          return _result(jsonEncode({'success': true, 'labels': labels}));
        },
      ),
      Tool(
        name: 'recall',
        description: 'Case-insensitive substring search over human labels.',
        inputSchema: {
          'type': 'object',
          'properties': {'query': {'type': 'string'}},
          'required': ['query'],
        },
        handler: (args) async {
          final query = (args['query'] as String? ?? '').toLowerCase();
          if (query.isEmpty) {
            return _result(jsonEncode({'success': false, 'error': 'query required'}));
          }
          final matches = map.entries
              .where((e) => e.humanLabel != null && e.humanLabel!.toLowerCase().contains(query))
              .map((e) => e.toJson())
              .toList();
          return _result(jsonEncode({'success': true, 'matches': matches}));
        },
      ),
    ];

Map<String, dynamic> _result(String text) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
    };
```

- [ ] **Step 3: Run tests + analyze**

- [ ] **Step 4: Commit**

```
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): memory tools (label_element, get_labels, recall)"
```

---

## Task 8: Set-of-Mark annotator (screenshot overlay)

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/enrich/som_annotator.dart`
- Create: `packages/flutter_qa_mcp/test/enrich/som_annotator_test.dart`

**Context:** Given the base64 PNG from `ext.qa.screenshot` and the element list with bounds, draw numbered boxes on each element's bounding rect. Output: new base64 PNG with overlays. Used by `screenshot(annotated=true)` in the perception tool.

Use the `image` package (`image: ^4.0.0`) for raster manipulation — small, pure-Dart, no native deps.

- [ ] **Step 1: Add image dependency**

In `packages/flutter_qa_mcp/pubspec.yaml` under `dependencies:`:
```yaml
  image: ^4.5.0
```

`dart pub get`.

- [ ] **Step 2: Failing test**

```dart
// packages/flutter_qa_mcp/test/enrich/som_annotator_test.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_qa_mcp/src/enrich/som_annotator.dart';
import 'package:image/image.dart';
import 'package:test/test.dart';

void main() {
  test('annotates a known PNG with one element box', () {
    // Generate a small black PNG inline.
    final src = Image(width: 400, height: 600);
    fill(src, color: ColorRgb8(0, 0, 0));
    final pngBytes = encodePng(src);
    final b64 = base64Encode(pngBytes);

    final annotated = SomAnnotator.annotate(
      pngBase64: b64,
      elements: [
        {
          'id': 'e_0',
          'bounds': {'x': 50.0, 'y': 100.0, 'w': 100.0, 'h': 40.0},
        },
      ],
    );

    final decoded = decodePng(base64Decode(annotated))!;
    expect(decoded.width, 400);
    expect(decoded.height, 600);
    // We could assert that *some* pixel in the box region differs from the original (drew a box).
    // For now we just confirm the output is a valid PNG of the expected size.
  });

  test('handles an empty element list by returning the input unchanged', () {
    final src = Image(width: 100, height: 100);
    fill(src, color: ColorRgb8(255, 255, 255));
    final b64 = base64Encode(encodePng(src));
    final result = SomAnnotator.annotate(pngBase64: b64, elements: const []);
    expect(decodePng(base64Decode(result))!.width, 100);
  });
}
```

- [ ] **Step 3: Implement**

```dart
// packages/flutter_qa_mcp/lib/src/enrich/som_annotator.dart
import 'dart:convert';
import 'package:image/image.dart';

class SomAnnotator {
  /// Annotates a base64 PNG with numbered boxes for each element with bounds.
  /// Element index = position in the input list. Numbering matches the agent's view.
  static String annotate({
    required String pngBase64,
    required List<Map<String, dynamic>> elements,
  }) {
    final bytes = base64Decode(pngBase64);
    final img = decodePng(bytes);
    if (img == null) return pngBase64;

    final outline = ColorRgb8(255, 80, 80);
    final fill = ColorRgba8(255, 80, 80, 200);

    for (var i = 0; i < elements.length; i++) {
      final el = elements[i];
      final bounds = el['bounds'] as Map?;
      if (bounds == null) continue;
      final x = (bounds['x'] as num).toInt();
      final y = (bounds['y'] as num).toInt();
      final w = (bounds['w'] as num).toInt();
      final h = (bounds['h'] as num).toInt();
      drawRect(img, x1: x, y1: y, x2: x + w, y2: y + h, color: outline, thickness: 2);
      // Number label in top-left corner of the box.
      drawString(
        img,
        '${i + 1}',
        font: arial14,
        x: x + 2,
        y: y + 2,
        color: outline,
      );
    }

    return base64Encode(encodePng(img));
  }
}
```

Note: `arial14`, `drawRect`, `drawString`, `decodePng`, `encodePng`, `Image`, `fill`, `ColorRgb8`, `ColorRgba8` come from `package:image/image.dart`. Verify the imports against the installed `image: ^4.5.0` API — some symbol names may differ slightly (e.g., older versions used `Color.fromRgb` instead of `ColorRgb8`). Adapt the code to the version you actually get.

- [ ] **Step 4: Wire `screenshot(annotated)` in `perception.dart`**

Modify `packages/flutter_qa_mcp/lib/src/tools/perception.dart`:

The existing `screenshot` tool takes no parameters and calls `ext.qa.screenshot`. Extend its `inputSchema` and handler:

```dart
Tool(
  name: 'screenshot',
  description: 'Returns a base64-encoded PNG of the current screen. If annotated=true, overlays numbered Set-of-Mark boxes on the current snapshot elements.',
  inputSchema: {
    'type': 'object',
    'properties': {'annotated': {'type': 'boolean'}},
  },
  handler: (args) async {
    final shotJson = await vm.callExtension('ext.qa.screenshot');
    final annotated = args['annotated'] == true;
    if (!annotated) {
      return _toolResult(jsonEncode(shotJson));
    }
    final snapJson = await vm.callExtension('ext.qa.snapshot');
    final elements = (snapJson['elements'] as List? ?? []).cast<Map<String, dynamic>>();
    final pngB64 = shotJson['data_base64'] as String;
    final annotatedPng = SomAnnotator.annotate(pngBase64: pngB64, elements: elements);
    return _toolResult(jsonEncode({
      ...shotJson,
      'data_base64': annotatedPng,
      'annotated': true,
      'element_count': elements.length,
    }));
  },
),
```

Add the import for `SomAnnotator`.

- [ ] **Step 5: Run tests + analyze**

```bash
cd packages/flutter_qa_mcp && dart test && dart analyze
```

- [ ] **Step 6: Commit**

```
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): Set-of-Mark screenshot annotator + screenshot(annotated)"
```

---

## Task 9: Enrich snapshot in the MCP-side snapshot tool

**Files:**
- Modify: `packages/flutter_qa_mcp/lib/src/tools/perception.dart`

**Context:** The current `snapshot` tool calls `ext.qa.snapshot` and returns the JSON directly. With the enricher and semantic map in place, wrap the response with `SnapshotEnricher.enrich`.

- [ ] **Step 1: Update perception.dart `snapshot` handler**

The current handler is:
```dart
handler: (_) async {
  final json = await vm.callExtension('ext.qa.snapshot');
  return _toolResult(jsonEncode(json));
},
```

Change `perceptionTools(VmClient vm)` to also accept a `SemanticMap`:
```dart
List<Tool> perceptionTools(VmClient vm, SemanticMap map) => [
      Tool(
        name: 'snapshot',
        description: 'Returns the denoised semantic tree of the visible screen, enriched with proposals and persistent labels.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          final raw = await vm.callExtension('ext.qa.snapshot');
          final enriched = SnapshotEnricher.enrich(raw: raw, map: map);
          return _toolResult(jsonEncode(enriched));
        },
      ),
      // ... inspect and screenshot unchanged in signature, but screenshot now has annotated param from Task 8 ...
    ];
```

Update `screenshot` similarly (no `map` needed; it already uses snapshot internally).

- [ ] **Step 2: Update the bin/ main to pass the map**

In `packages/flutter_qa_mcp/bin/flutter_qa_mcp.dart`, before building the tool list:
```dart
final map = SemanticMap(projectRoot: Directory.current.path);
await map.load();
```

Then:
```dart
final protocol = McpProtocol(tools: [
  ...perceptionTools(vm, map),
  ...actionTools(vm),
  ...syncTools(vm),
  ...memoryTools(map),
]);
```

Add the imports.

- [ ] **Step 3: Update perception_tools_test if any (none currently exist; we're fine)**

- [ ] **Step 4: Run tests + analyze**

- [ ] **Step 5: Commit**

```
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): wire enricher and memory tools into CLI"
```

---

## Task 10: Dashboard HTTP server scaffold

**Files:**
- Create: `packages/flutter_qa_mcp/lib/src/dashboard/server.dart`
- Create: `packages/flutter_qa_mcp/test/dashboard/server_test.dart`

**Context:** A `shelf`-based HTTP server bound to localhost:7345 by default. Two route groups: `/api/*` (JSON) and `/` (static frontend).

- [ ] **Step 1: Add shelf deps**

In `packages/flutter_qa_mcp/pubspec.yaml` under `dependencies:`:
```yaml
  shelf: ^1.4.0
  shelf_router: ^1.1.0
```

`dart pub get`.

- [ ] **Step 2: Failing test**

```dart
// packages/flutter_qa_mcp/test/dashboard/server_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_qa_mcp/src/dashboard/server.dart';
import 'package:flutter_qa_mcp/src/map/map_record.dart';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:test/test.dart';

void main() {
  late DashboardServer server;
  late SemanticMap map;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dashboard_test_');
    map = SemanticMap(projectRoot: tmp.path);
    map.upsert(MapEntry(fingerprint: 'f_1', humanLabel: 'Checkout'));
    server = DashboardServer(map: map);
    await server.start(port: 0);  // 0 = OS-assigned port
  });

  tearDown(() async {
    await server.stop();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('GET /api/labels returns persisted labels', () async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('http://localhost:${server.port}/api/labels'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final parsed = jsonDecode(body) as Map<String, dynamic>;
    expect(parsed['labels'], isA<List>());
    expect((parsed['labels'] as List).first['human_label'], 'Checkout');
    client.close();
  });

  test('GET / returns HTML', () async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('http://localhost:${server.port}/'));
    final resp = await req.close();
    expect(resp.statusCode, 200);
    expect(resp.headers.contentType?.mimeType, 'text/html');
    client.close();
  });
}
```

- [ ] **Step 3: Implement**

```dart
// packages/flutter_qa_mcp/lib/src/dashboard/server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../map/map_record.dart';
import '../map/semantic_map.dart';

class DashboardServer {
  DashboardServer({required this.map});
  final SemanticMap map;

  HttpServer? _server;
  int get port => _server?.port ?? 0;

  Future<void> start({int port = 7345, String host = 'localhost'}) async {
    final router = Router()
      ..get('/api/labels', _getLabels)
      ..get('/api/unresolved', _getUnresolved)
      ..post('/api/label', _postLabel)
      ..post('/api/dismiss', _postDismiss)
      ..get('/', _serveIndex)
      ..get('/main.js', _serveJs)
      ..get('/style.css', _serveCss);

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, host, port);
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  Response _getLabels(Request request) {
    final labels = map.entries
        .where((e) => e.humanLabel != null)
        .map((e) => e.toJson())
        .toList();
    return Response.ok(
      jsonEncode({'labels': labels}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _getUnresolved(Request request) {
    final unresolved = map.entries
        .where((e) => e.humanLabel == null && !e.dismissed)
        .map((e) => e.toJson())
        .toList();
    return Response.ok(
      jsonEncode({'unresolved': unresolved}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _postLabel(Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final fp = body['fingerprint'] as String?;
    final name = body['name'] as String?;
    if (fp == null || name == null) {
      return Response.badRequest(body: jsonEncode({'error': 'fingerprint and name required'}));
    }
    final existing = map.get(fp);
    if (existing == null) {
      map.upsert(MapEntry(fingerprint: fp, humanLabel: name, observationCount: 1));
    } else {
      existing.humanLabel = name;
    }
    await map.save();
    return Response.ok(jsonEncode({'success': true}), headers: {'content-type': 'application/json'});
  }

  Future<Response> _postDismiss(Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final fp = body['fingerprint'] as String?;
    if (fp == null) {
      return Response.badRequest(body: jsonEncode({'error': 'fingerprint required'}));
    }
    final existing = map.get(fp);
    if (existing != null) {
      existing.dismissed = true;
    } else {
      map.upsert(MapEntry(fingerprint: fp, dismissed: true));
    }
    await map.save();
    return Response.ok(jsonEncode({'success': true}), headers: {'content-type': 'application/json'});
  }

  Response _serveIndex(Request request) => Response.ok(
        _indexHtml,
        headers: {'content-type': 'text/html'},
      );

  Response _serveJs(Request request) => Response.ok(
        _mainJs,
        headers: {'content-type': 'application/javascript'},
      );

  Response _serveCss(Request request) => Response.ok(
        _styleCss,
        headers: {'content-type': 'text/css'},
      );
}

// Static frontend assets. Plan 3 Task 11 will replace these with richer content.
const String _indexHtml = '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Flutter QA Review</title>
    <link rel="stylesheet" href="/style.css">
  </head>
  <body>
    <h1>Flutter QA Review</h1>
    <div id="root">Loading…</div>
    <script src="/main.js"></script>
  </body>
</html>
''';

const String _mainJs = '''
async function load() {
  const root = document.getElementById('root');
  root.textContent = 'Dashboard scaffold — Task 11 will fill this in.';
}
load();
''';

const String _styleCss = '''
body { font-family: -apple-system, sans-serif; margin: 2rem; }
''';
```

- [ ] **Step 4: Run tests + analyze**

- [ ] **Step 5: Commit**

```
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): dashboard HTTP server scaffold (shelf)"
```

---

## Task 11: Dashboard frontend

**Files:**
- Modify: `packages/flutter_qa_mcp/lib/src/dashboard/server.dart` (replace the static HTML/JS/CSS constants)

**Context:** Single-page vanilla JS app. Polls `/api/unresolved` every 3s. Renders a list with: fingerprint, screen_context, top proposal, "Accept" / "Edit" / "Dismiss" buttons. The user can curate the entire map without leaving the page.

- [ ] **Step 1: Replace `_indexHtml`, `_mainJs`, `_styleCss`**

Update them in place (don't introduce a separate file system for this v1 — keeping them as Dart string constants keeps the MCP server a single-binary).

```html
<!-- _indexHtml -->
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Flutter QA Review</title>
    <link rel="stylesheet" href="/style.css">
  </head>
  <body>
    <header>
      <h1>Flutter QA — Review</h1>
      <div id="status" class="status">…</div>
    </header>
    <main>
      <section>
        <h2>Unresolved (<span id="unresolved-count">0</span>)</h2>
        <ul id="unresolved-list" class="list"></ul>
      </section>
      <section>
        <h2>Labeled (<span id="labeled-count">0</span>)</h2>
        <ul id="labeled-list" class="list compact"></ul>
      </section>
    </main>
    <script src="/main.js"></script>
  </body>
</html>
```

```js
// _mainJs
const POLL_MS = 3000;

async function fetchJson(url, opts) {
  const res = await fetch(url, opts);
  if (!res.ok) throw new Error(res.statusText);
  return res.json();
}

function el(tag, attrs = {}, children = []) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'onclick') e.addEventListener('click', v);
    else e.setAttribute(k, v);
  }
  for (const c of children) {
    e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
  }
  return e;
}

function renderUnresolved(entry) {
  const fp = entry.fingerprint;
  const top = (entry.proposals || []).sort((a, b) => b.confidence - a.confidence)[0];
  const labelHint = top ? `${top.label} (from ${top.source}, ${(top.confidence * 100) | 0}%)` : '—';

  const input = el('input', {type: 'text', placeholder: top ? top.label : 'Enter label…'});

  const accept = el('button', {
    onclick: async () => {
      const name = (input.value || (top && top.label) || '').trim();
      if (!name) return;
      await fetchJson('/api/label', {
        method: 'POST',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({fingerprint: fp, name}),
      });
      refresh();
    },
  }, ['Accept']);

  const dismiss = el('button', {
    onclick: async () => {
      await fetchJson('/api/dismiss', {
        method: 'POST',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({fingerprint: fp}),
      });
      refresh();
    },
  }, ['Dismiss']);

  return el('li', {}, [
    el('div', {class: 'fp'}, [fp]),
    el('div', {class: 'meta'}, [
      entry.creation_location || '(no source location)',
      ' • ',
      entry.screen_context || '(unknown screen)',
    ]),
    el('div', {class: 'hint'}, ['Proposal: ', labelHint]),
    el('div', {class: 'actions'}, [input, accept, dismiss]),
  ]);
}

function renderLabeled(entry) {
  return el('li', {}, [
    el('strong', {}, [entry.human_label || '(unlabeled)']),
    ' — ',
    el('code', {}, [entry.fingerprint]),
    ' (',
    String(entry.observation_count || 0),
    ' observations)',
  ]);
}

async function refresh() {
  document.getElementById('status').textContent = 'Refreshing…';
  try {
    const [unresolved, labeled] = await Promise.all([
      fetchJson('/api/unresolved'),
      fetchJson('/api/labels'),
    ]);
    const u = unresolved.unresolved || [];
    const l = labeled.labels || [];
    document.getElementById('unresolved-count').textContent = String(u.length);
    document.getElementById('labeled-count').textContent = String(l.length);

    const ul = document.getElementById('unresolved-list');
    ul.replaceChildren(...u.map(renderUnresolved));
    const ll = document.getElementById('labeled-list');
    ll.replaceChildren(...l.map(renderLabeled));

    document.getElementById('status').textContent = `Updated ${new Date().toLocaleTimeString()}`;
  } catch (e) {
    document.getElementById('status').textContent = `Error: ${e.message}`;
  }
}

refresh();
setInterval(refresh, POLL_MS);
```

```css
/* _styleCss */
* { box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 2rem; color: #1a1a1a; background: #fafafa; }
header { display: flex; justify-content: space-between; align-items: baseline; border-bottom: 1px solid #ddd; padding-bottom: 0.5rem; margin-bottom: 1.5rem; }
.status { font-size: 0.85rem; color: #666; }
section { margin-bottom: 2rem; }
.list { list-style: none; padding: 0; }
.list li { padding: 1rem; background: white; border: 1px solid #e5e5e5; border-radius: 6px; margin-bottom: 0.75rem; }
.list.compact li { padding: 0.4rem 0.75rem; font-size: 0.9rem; }
.fp { font-family: monospace; font-size: 0.8rem; color: #888; }
.meta { font-size: 0.85rem; color: #555; margin: 0.25rem 0; }
.hint { font-size: 0.95rem; margin: 0.25rem 0; color: #224; }
.actions { display: flex; gap: 0.5rem; margin-top: 0.5rem; }
.actions input { flex: 1; padding: 0.5rem; border: 1px solid #ccc; border-radius: 4px; }
button { padding: 0.5rem 1rem; border: 1px solid #ccc; background: white; cursor: pointer; border-radius: 4px; }
button:hover { background: #f0f0f0; }
code { font-family: monospace; background: #eee; padding: 1px 4px; border-radius: 3px; }
```

These are Dart triple-quoted string constants in `server.dart`. Watch for `$` characters in the JS — they need to be escaped (`\$`) inside Dart string literals, OR use raw string literals (`r''' ... '''`).

**Strong recommendation:** use raw strings (`r'''...'''`) for the JS and CSS constants so you don't have to escape every `${var}` template literal in the JS.

- [ ] **Step 2: Manually verify**

Start the server in a test or one-off:
```dart
final m = SemanticMap(projectRoot: '/tmp');
m.upsert(MapEntry(fingerprint: 'f_test', humanLabel: 'Test'));
final s = DashboardServer(map: m);
await s.start();
print('http://localhost:${s.port}');
```

Open in a browser, confirm the layout renders and the polling shows the labeled entry. This is a manual verification — no automated test.

- [ ] **Step 3: Test + analyze**

The existing dashboard_test still passes (it only checks `/api/labels` and `/` return 200; doesn't assert HTML content).

- [ ] **Step 4: Commit**

```
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): dashboard frontend (single-page review UI)"
```

---

## Task 12: `flutter-qa-mcp review` subcommand

**Files:**
- Modify: `packages/flutter_qa_mcp/bin/flutter_qa_mcp.dart`

**Context:** Add a subcommand mode: `flutter-qa-mcp review` starts the dashboard server on port 7345 and prints the URL. No MCP server / VM connection in this mode.

- [ ] **Step 1: Refactor the CLI to dispatch on first positional argument**

```dart
// packages/flutter_qa_mcp/bin/flutter_qa_mcp.dart
Future<void> main(List<String> args) async {
  // First positional arg = subcommand (default = serve MCP)
  final subcommand = args.firstWhere(
    (a) => !a.startsWith('-'),
    orElse: () => 'serve',
  );

  switch (subcommand) {
    case 'review':
      return _runReview(args.where((a) => a != 'review').toList());
    case 'serve':
    default:
      return _runServe(args.where((a) => a != 'serve').toList());
  }
}

Future<void> _runReview(List<String> args) async {
  final port = int.tryParse(_argValue(args, '--port') ?? '7345') ?? 7345;
  final root = _argValue(args, '--project-root') ?? Directory.current.path;
  final map = SemanticMap(projectRoot: root);
  await map.load();
  final server = DashboardServer(map: map);
  await server.start(port: port);
  stdout.writeln('Dashboard running at http://localhost:${server.port}');
  stdout.writeln('Press Ctrl+C to stop.');
  await ProcessSignal.sigint.watch().first;
  await server.stop();
}

Future<void> _runServe(List<String> args) async {
  // ... existing CLI logic for attach + tools, unchanged ...
}

String? _argValue(List<String> args, String name) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == name) return args[i + 1];
  }
  return null;
}
```

The existing `--attach` / `--version` / `--help` argparse logic lives entirely in `_runServe`. The `_runReview` path is independent and uses `--port` + `--project-root` flags only.

- [ ] **Step 2: Smoke test**

```bash
cd packages/flutter_qa_mcp
dart run bin/flutter_qa_mcp.dart review --port 0  # 0 lets OS pick; prints URL then waits
# Press Ctrl+C to stop. Verify the URL was printed and the process exited cleanly.
```

You can't easily script this verification (the process blocks until SIGINT). Manual is acceptable.

- [ ] **Step 3: Run all non-e2e tests + analyze**

```bash
dart test
dart analyze
```

- [ ] **Step 4: Commit**

```
git add packages/flutter_qa_mcp/
git commit -m "feat(mcp): flutter-qa-mcp review subcommand starts dashboard"
```

---

## Task 13: E2E test — label_element → snapshot reflects label

**Files:**
- Create: `packages/flutter_qa_mcp/test/e2e/augmentation_e2e_test.dart`

**Context:** Boot demo app, snapshot, observe an unresolved element (one of the delete `GestureDetector`s with no text), label its fingerprint via `label_element`, snapshot again, confirm the element now appears in `elements[]` with `label_source: 'human'`.

- [ ] **Step 1: Implement**

```dart
// packages/flutter_qa_mcp/test/e2e/augmentation_e2e_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/tools/action_tools.dart';
import 'package:flutter_qa_mcp/src/tools/memory_tools.dart';
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
    late Directory tmp;
    late SemanticMap map;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('aug_e2e_');
      map = SemanticMap(projectRoot: tmp.path);
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
        ...perceptionTools(vm, map),
        ...actionTools(vm),
        ...syncTools(vm),
        ...memoryTools(map),
      ]);
    });

    tearDownAll(() async {
      await vm.dispose();
      flutter.kill();
      await flutter.exitCode;
      if (tmp.existsSync()) await tmp.delete(recursive: true);
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

    test('label_element promotes an unresolved element to resolved', () async {
      // Navigate to cart screen so we have delete GestureDetectors.
      final home = await callTool('snapshot', {});
      final goToCart = (home['elements'] as List).firstWhere(
        (e) => (e as Map)['label'] == 'Go to cart',
      ) as Map;
      await callTool('tap', {'element_id': goToCart['id']});
      await callTool('wait_for_route', {'route': '/cart', 'timeout_ms': 5000});

      final cart = await callTool('snapshot', {});
      final unresolved = (cart['unresolved'] as List? ?? []);
      expect(unresolved, isNotEmpty, reason: 'expected at least one unresolved tappable on cart screen');

      final target = unresolved.first as Map;
      final fp = target['fingerprint'] as String;

      final labelResp = await callTool('label_element', {
        'fingerprint': fp,
        'name': 'Delete Item',
      });
      expect(labelResp['success'], isTrue);

      final after = await callTool('snapshot', {});
      final resolvedMatch = (after['elements'] as List).any(
        (e) => (e as Map)['fingerprint'] == fp && e['label'] == 'Delete Item',
      );
      expect(resolvedMatch, isTrue);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }, tags: ['e2e']);
}
```

- [ ] **Step 2: Confirm unit tests still pass (e2e auto-skipped)**

```bash
cd packages/flutter_qa_mcp && dart test && dart analyze
cd ../flutter_qa_probe && flutter test && flutter analyze
```

- [ ] **Step 3: Commit**

```
git add packages/flutter_qa_mcp/
git commit -m "test(e2e): augmentation flow — label_element promotes unresolved"
```

---

## Done state

After all tasks land:

- MCP tool count: **19** (3 perception + 7 action + 3 sync + 3 memory + 1 dashboard subcommand + others). The full agent surface from the spec is implemented.
- `unresolved[]` array is emitted in every snapshot, with `source_location` proposals from AST parsing.
- `.flutter_qa/map.json` persists across runs; human labels promote unresolved → resolved automatically.
- `flutter-qa-mcp review` opens a localhost dashboard for human curation.
- `screenshot(annotated=true)` returns a Set-of-Mark overlay PNG for VLM grounding.
- VLM proposals: agent can call `screenshot(annotated=true)` + reason about the boxes + call `label_element` with `source=vlm` notes — closing the augmentation loop end-to-end without any persistent map plumbing on the agent's side.
- All unit tests pass; one new E2E test demonstrates the labeling loop.
- `analyzer` package moved to where it actually runs (MCP, host-side).

This completes the spec.
