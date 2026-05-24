import 'package:agent_wires_probe/src/tree/snapshot_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'elements buried under a topmost full-screen route are dropped from snapshot',
      (tester) async {
    // Two-page Navigator: an underneath page with a labelled FAB ("Buried"),
    // and a topmost page covering the viewport with its own button
    // ("Visible"). Flutter mounts both, but the user only sees Visible.
    // The agent should not be tempted to tap Buried.
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        pages: const [
          MaterialPage(
            name: 'UnderRoute',
            child: Scaffold(
              floatingActionButton: FloatingActionButton(
                onPressed: null,
                child: Text('Buried'),
              ),
              body: Center(child: Text('underneath body')),
            ),
          ),
          MaterialPage(
            name: 'TopRoute',
            child: Scaffold(body: Center(child: Text('Visible'))),
          ),
        ],
        onDidRemovePage: _noop,
      ),
    ));
    await tester.pumpAndSettle();

    final snap = SnapshotBuilder.build();
    final allLabels = [
      ...snap.elements.map((e) => e.label),
      ...snap.unresolved.map((e) => e.label),
    ].whereType<String>().toList();
    expect(allLabels, contains('Visible'),
        reason: 'topmost route content must be in the snapshot');
    expect(allLabels, isNot(contains('Buried')),
        reason: 'underneath route content must be filtered as occluded');
    expect(allLabels, isNot(contains('underneath body')),
        reason: 'all underneath descendants are occluded, not just the FAB');
  });

  testWidgets(
      'modal dialog: dialog is visible, page beneath the modal barrier is occluded',
      (tester) async {
    // showDialog pushes [page, modalBarrier, dialog]. The modal barrier
    // covers the whole viewport (its job is to intercept taps everywhere
    // except the dialog), so the page beneath is functionally occluded
    // from the agent's perspective — taps there would just dismiss the
    // dialog, not hit the page button. The dialog itself stays visible.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => const AlertDialog(content: Text('Dialog text')),
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    final snap = SnapshotBuilder.build();
    final allLabels = [
      ...snap.elements.map((e) => e.label),
      ...snap.unresolved.map((e) => e.label),
    ].whereType<String>().toList();
    expect(allLabels, contains('Dialog text'),
        reason: 'dialog itself stays in the snapshot');
    expect(allLabels, isNot(contains('Open Dialog')),
        reason: 'the modal barrier covers the page; page button is no '
            'longer tappable so the agent should not see it');
  });

  testWidgets('single-page Navigator is unaffected (no occlusion to apply)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: ElevatedButton(
          onPressed: () {},
          child: const Text('OnlyButton'),
        )),
      ),
    ));
    await tester.pumpAndSettle();

    final snap = SnapshotBuilder.build();
    final allLabels = snap.elements.map((e) => e.label).whereType<String>();
    expect(allLabels, contains('OnlyButton'));
  });

  testWidgets('snapshot._debug.occlusion surfaces per-theater diagnostics',
      (tester) async {
    // The diagnostic field exists so the agent can verify the new walker
    // code actually ran and explain when an entry didn't register as
    // covering. Smoke-test the shape; specific counts are exercised
    // elsewhere.
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        pages: const [
          MaterialPage(name: 'A', child: Scaffold(body: SizedBox.expand())),
          MaterialPage(name: 'B', child: Scaffold(body: SizedBox.expand())),
        ],
        onDidRemovePage: _noop,
      ),
    ));
    await tester.pumpAndSettle();

    final snap = SnapshotBuilder.build();
    final debug = snap.toJson()['_debug'] as Map?;
    final occlusion = debug?['occlusion'] as Map?;
    expect(occlusion, isNotNull);
    expect(occlusion!['viewport_found'], isTrue);
    expect(occlusion['theaters_found'], greaterThan(0));
    final theaters = occlusion['theaters'] as List?;
    expect(theaters, isNotNull);
    // The inner Navigator's theater has 2 entries; details should reflect that.
    final twoEntryTheater = (theaters! as List).cast<Map>().firstWhere(
          (t) => t['entry_count'] == 2,
          orElse: () => const {},
        );
    expect(twoEntryTheater, isNotEmpty,
        reason: '_debug.theaters should describe the 2-entry inner Navigator');
    expect(twoEntryTheater['top_covering_idx'], 1);
    final entryList = twoEntryTheater['entries'] as List;
    expect(entryList, hasLength(2));
    expect((entryList.last as Map)['covers'], isTrue);
  });

  testWidgets(
      'covering uses containment of the theater box, not just the global window',
      (tester) async {
    // device_preview / shrink-wrap-style setups lay pages out smaller than
    // physicalSize. A page that fully covers the theater rect (say 300×600
    // inside a 440×956 window) must still register as covering — otherwise
    // we never drop the page beneath it. We simulate this by placing the
    // Navigator inside a SizedBox; the Navigator's bounds become smaller
    // than the test window.
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 500,
          child: Navigator(
            pages: const [
              MaterialPage(
                name: 'Beneath',
                child: Scaffold(body: Center(child: Text('UNDER'))),
              ),
              MaterialPage(
                name: 'OnTop',
                child: Scaffold(body: Center(child: Text('TOP'))),
              ),
            ],
            onDidRemovePage: _noop,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final snap = SnapshotBuilder.build();
    final labels = [
      ...snap.elements.map((e) => e.label),
      ...snap.unresolved.map((e) => e.label),
    ].whereType<String>().toList();
    expect(labels, contains('TOP'));
    expect(labels, isNot(contains('UNDER')),
        reason: 'top page covers the 300×500 theater box (not the global '
            'window) — under page must still be dropped');
  });
}

void _noop(Page<Object?> _) {}
