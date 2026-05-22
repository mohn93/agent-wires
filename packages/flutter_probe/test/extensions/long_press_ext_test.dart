import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_probe/src/extensions/long_press_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long_press on a GestureDetector triggers onLongPress', (tester) async {
    var longPresses = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          onLongPress: () => longPresses++,
          child: const SizedBox(width: 100, height: 100, child: ColoredBox(color: Color(0xFF000000))),
        ),
      ),
    ));

    // Try a range of ids to find the GestureDetector (Listener widgets may appear first).
    bool triggered = false;
    for (var i = 0; i < 10 && !triggered; i++) {
      final resp = await tester.runAsync(
        () => LongPressExtension.handle('ext.qa.long_press', {
          'element_id': 'e_$i',
          'duration_ms': '600',
        }),
      );
      if (resp != null) {
        final body = jsonDecode(resp.result!) as Map<String, dynamic>;
        if (body['success'] == true) {
          await tester.pumpAndSettle();
          if (longPresses > 0) triggered = true;
        }
      }
    }
    expect(longPresses, greaterThanOrEqualTo(1));
  });
}
