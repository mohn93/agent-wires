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

  testWidgets('subtree dedup: ElevatedButton produces exactly one element', (tester) async {
    // Each Flutter button wraps several promoted-on-their-own widgets
    // (Material InkWell, GestureDetector, Listener). Without dedup, this
    // produced ~4 entries per button — overwhelming an LLM on real apps.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(onPressed: () {}, child: const Text('Submit')),
        ),
      ),
    ));

    final snap = SnapshotBuilder.build();
    final entries =
        [...snap.elements, ...snap.unresolved].where((e) => e.label == 'Submit');
    expect(entries, hasLength(1),
        reason: 'expected one element for the button, got ${entries.length}: '
            '${entries.map((e) => e.widgetType).toList()}');
    expect(entries.first.widgetType, 'ElevatedButton');
    expect(entries.first.role, 'button');
  });

  testWidgets('bare EditableText (custom PIN-style widget) lands in snapshot',
      (tester) async {
    // Custom OTP / PIN widgets wrap EditableText directly without going
    // through TextField. Promoting EditableText lets the agent see those
    // inputs and target them with enter_text.
    final controller = TextEditingController();
    final focus = FocusNode();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 40,
          height: 40,
          child: EditableText(
            controller: controller,
            focusNode: focus,
            style: const TextStyle(),
            cursorColor: const Color(0xFF000000),
            backgroundCursorColor: const Color(0xFF000000),
          ),
        ),
      ),
    ));

    final snap = SnapshotBuilder.build();
    final editables = snap.unresolved
        .where((e) => e.widgetType == 'EditableText')
        .toList();
    expect(editables, hasLength(1));
    expect(editables.first.role, 'textfield');
  });

  testWidgets('a TextField produces only one entry (its EditableText is deduped)',
      (tester) async {
    // Regression: promoting EditableText shouldn't double-count vanilla
    // TextFields. The bounds-similarity dedup collapses the inner
    // EditableText into the surrounding TextField.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField()),
    ));
    final snap = SnapshotBuilder.build();
    final tfs = [...snap.elements, ...snap.unresolved]
        .where((e) =>
            e.widgetType == 'TextField' || e.widgetType == 'EditableText')
        .toList();
    expect(tfs, hasLength(1));
    expect(tfs.first.widgetType, 'TextField');
  });

  testWidgets(
      'card-sized GestureDetector with inner IconButton survives (DNS-row pattern)',
      (tester) async {
    // Custom row widgets (DNS records, invoice items) wrap a few Text
    // widgets in a GestureDetector and stick action IconButtons inside.
    // The OLD rule dropped the outer GestureDetector ("generic + named
    // descendant = plumbing") so the agent saw only the IconButtons —
    // 8 "delete" buttons with no way to tell which record they belonged
    // to. The bounds-aware rule keeps card-sized wrappers; only
    // viewport-spanning generic wrappers (Scaffold's internal Listener)
    // still get dropped.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 80,
          child: GestureDetector(
            onTap: () {},
            child: Row(
              children: [
                const Expanded(child: Text('NS mohanned.ly')),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.delete),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    final snap = SnapshotBuilder.build();
    final all = [...snap.elements, ...snap.unresolved];
    final row = all.where((e) => e.widgetType == 'GestureDetector').toList();
    final delete = all.where((e) => e.widgetType == 'IconButton').toList();
    expect(row, hasLength(1),
        reason: 'card-sized GestureDetector must survive');
    expect(delete, hasLength(1),
        reason: 'inner IconButton must also survive');
    expect(row.first.label, contains('NS mohanned.ly'));
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
