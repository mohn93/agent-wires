import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_probe/src/extensions/inspect_ext.dart';
import 'package:flutter_probe/src/extensions/snapshot_ext.dart';
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
}
