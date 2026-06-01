import 'package:agent_wires_probe/src/tree/snapshot_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'elements inside IgnorePointer(ignoring:true) are not surfaced as tappable',
      (tester) async {
    // This is the "phantom FAB" case: an expandable FAB keeps its collapsed
    // sub-items mounted and laid out, but wraps each one in
    // IgnorePointer(ignoring: !open). A real tap can't reach them, so the
    // agent must not see them as tappable targets (tapping landed on the row
    // behind them in the field report).
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            ElevatedButton(onPressed: () {}, child: const Text('RealButton')),
            IgnorePointer(
              ignoring: true,
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('GhostButton'),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final snap = SnapshotBuilder.build();
    final labels = [
      ...snap.elements.map((e) => e.label),
      ...snap.unresolved.map((e) => e.label),
    ].whereType<String>().toList();
    expect(labels, contains('RealButton'));
    expect(labels, isNot(contains('GhostButton')),
        reason: 'a pointer-ignored element cannot be tapped, so it must not '
            'appear in the snapshot');
  });

  testWidgets('IgnorePointer(ignoring:false) keeps its subtree visible',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IgnorePointer(
          ignoring: false,
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('LiveButton'),
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
    expect(labels, contains('LiveButton'),
        reason: 'ignoring:false does not block taps, so it stays visible');
  });

  testWidgets('elements inside AbsorbPointer(absorbing:true) are not surfaced',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AbsorbPointer(
          absorbing: true,
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('AbsorbedButton'),
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
    expect(labels, isNot(contains('AbsorbedButton')),
        reason: 'an absorbed-pointer element cannot be tapped');
  });
}
