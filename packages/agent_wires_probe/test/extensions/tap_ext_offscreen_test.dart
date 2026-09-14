import 'dart:convert';
import 'package:agent_wires_probe/src/extensions/tap_ext.dart';
import 'package:agent_wires_probe/src/tree/snapshot_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _idOf(Key key) {
  final kept = SnapshotBuilder.keptNodes();
  for (var i = 0; i < kept.length; i++) {
    if (kept[i].element.widget.key == key) return 'e_$i';
  }
  throw StateError('no kept node with key $key');
}

void main() {
  testWidgets('tap refuses an element whose center is outside the viewport',
      (tester) async {
    var taps = 0;
    const far = Key('far');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            const SizedBox(height: 2000),
            ElevatedButton(
              key: far,
              onPressed: () => taps++,
              child: const Text('Far'),
            ),
          ]),
        ),
      ),
    ));

    final resp =
        await TapExtension.handle('ext.qa.tap', {'element_id': _idOf(far)});
    await tester.pumpAndSettle();

    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
    expect(body['error'], contains('outside the viewport'));
    expect(taps, 0);
  });
}
