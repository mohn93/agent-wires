import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/snapshot_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('handleSnapshot returns JSON with route and elements', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () {}, child: const Text('Tap me')),
      ),
    ));

    final resp = await SnapshotExtension.handle('ext.qa.snapshot', const {});
    expect(resp.isError(), isFalse);
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['elements'], isA<List>());
    final hasButton = (body['elements'] as List)
        .any((e) => (e as Map)['widget_type'] == 'ElevatedButton');
    expect(hasButton, isTrue);
  });
}
