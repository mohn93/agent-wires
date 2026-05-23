import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/inspect_ext.dart';
import 'package:agent_wires_probe/src/extensions/snapshot_ext.dart';
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
    expect(resp.isError(), isFalse);
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['ancestor_types'], isA<List>());
    expect(body['widget_type'], isNotNull);
  });

  test('inspect with missing element_id returns error', () async {
    final resp = await InspectExtension.handle('ext.qa.inspect', const {});
    expect(resp.isError(), isTrue);
  });

  testWidgets(
      'inspect returns descendants subtree by default with visible_text',
      (tester) async {
    // ElevatedButton wraps its child (Text "Submit") in several layers
    // (Material, InkWell, Padding, etc.). Inspecting the button must reveal
    // the inner Text via the descendants[] subtree — exactly what the agent
    // asked for ("the TextField inside this Card" scenario).
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(
          onPressed: () {},
          child: const Text('Submit'),
        ),
      ),
    ));

    final snapResp =
        await SnapshotExtension.handle('ext.qa.snapshot', const {});
    final snap = jsonDecode(snapResp.result!) as Map<String, dynamic>;
    final elements =
        ((snap['elements'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final unresolved = ((snap['unresolved'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final all = [...elements, ...unresolved];
    // Pick the ElevatedButton (or any Button-named entry) — its descendants
    // include the inner Text.
    final button = all.firstWhere(
      (e) => (e['widget_type'] as String?)?.contains('Button') ?? false,
    );
    final id = button['id'] as String;

    // ElevatedButton wraps its child in ~25 Material layers before reaching
    // Text — bump descendant_depth high enough that 'Submit' is reachable.
    final resp = await InspectExtension.handle('ext.qa.inspect', {
      'element_id': id,
      'descendant_depth': '60',
    });
    expect(resp.isError(), isFalse);
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['descendants'], isA<List>());
    final descendants =
        (body['descendants'] as List).cast<Map<String, dynamic>>();
    final texts = descendants
        .map((d) => d['visible_text'])
        .whereType<String>()
        .toList();
    expect(texts, contains('Submit'),
        reason: 'descendants should expose the inner Text widget');
  });

  testWidgets('inspect skips descendants when include_descendants:false',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(
          onPressed: () {},
          child: const Text('x'),
        ),
      ),
    ));
    final snapResp =
        await SnapshotExtension.handle('ext.qa.snapshot', const {});
    final snap = jsonDecode(snapResp.result!) as Map<String, dynamic>;
    final id = ((snap['elements'] as List).first as Map)['id'] as String;

    final resp = await InspectExtension.handle('ext.qa.inspect', {
      'element_id': id,
      'include_descendants': 'false',
    });
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body.containsKey('descendants'), isFalse);
  });
}
