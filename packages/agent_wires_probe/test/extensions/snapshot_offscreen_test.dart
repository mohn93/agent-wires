import 'dart:convert';
import 'package:agent_wires_probe/src/extensions/snapshot_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('elements laid out below the viewport are flagged offscreen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            ElevatedButton(onPressed: () {}, child: const Text('Near')),
            const SizedBox(height: 2000),
            ElevatedButton(onPressed: () {}, child: const Text('Far')),
          ]),
        ),
      ),
    ));

    final resp = await SnapshotExtension.handle('ext.qa.snapshot', const {});
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    final elements = (body['elements'] as List).cast<Map<String, dynamic>>();
    final near = elements.firstWhere((e) => e['label'] == 'Near');
    final far = elements.firstWhere((e) => e['label'] == 'Far');
    expect(near.containsKey('offscreen'), isFalse);
    expect(far['offscreen'], isTrue);
  });
}
