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
}

void _noop(Page<Object?> _) {}
