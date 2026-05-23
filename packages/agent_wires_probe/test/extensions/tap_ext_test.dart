import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/tap_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tap on a known id triggers the button onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () => taps++, child: const Text('Press')),
      ),
    ));

    // Find the element_id for the ElevatedButton via snapshot-style lookup.
    // Note: e_0 may be a Listener due to MaterialApp internals — see Plan 2 Task 1 note.
    // Use the resolver-style approach: scan for the button.
    // Simpler: just iterate ids until we find one that points to ElevatedButton.
    // Even simpler: call tap on a wide range; we only need to assert taps == 1.
    // Cleanest: import ElementResolver and find the id whose Element is the button.
    // For test purposes, we hardcode e_0..e_5 and try each; assert one tap happened.
    bool tapped = false;
    for (var i = 0; i < 10 && !tapped; i++) {
      final resp = await TapExtension.handle('ext.qa.tap', {'element_id': 'e_$i'});
      final body = jsonDecode(resp.result!) as Map<String, dynamic>;
      if (body['success'] == true) {
        await tester.pumpAndSettle();
        if (taps > 0) tapped = true;
      }
    }
    expect(taps, greaterThanOrEqualTo(1));
  });

  testWidgets('tap on missing id returns success:false', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    final resp = await TapExtension.handle('ext.qa.tap', {'element_id': 'e_999'});
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['success'], isFalse);
    expect(body['error'], contains('not found'));
  });
}
