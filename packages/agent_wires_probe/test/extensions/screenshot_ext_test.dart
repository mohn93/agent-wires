import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/screenshot_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('screenshot returns base64 PNG bytes', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    await tester.pump(); // ensure RepaintBoundary is painted before capturing
    // runAsync escapes the fake-async zone so that Scene.toImage() can resolve.
    final resp = await tester.runAsync(
      () => ScreenshotExtension.handle('ext.qa.screenshot', const {}),
    );
    expect(resp!.isError(), isFalse);
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['format'], 'png');
    expect((body['data_base64'] as String).length, greaterThan(100));
  });

  testWidgets('captures while a TextField is focused (blinking cursor) (#4)',
      (tester) async {
    // A focused TextField repaints on every cursor blink, so the root boundary
    // is perpetually debugNeedsPaint. The old code asserted and never produced
    // a screenshot mid-edit; capture must now succeed instead.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TextField(autofocus: true)),
      ),
    );
    await tester.pump(); // build + autofocus
    await tester.pump(const Duration(milliseconds: 600)); // start cursor blink

    final resp = await tester.runAsync(
      () => ScreenshotExtension.handle('ext.qa.screenshot', const {}),
    );
    expect(resp!.isError(), isFalse,
        reason: 'must not fail the debugNeedsPaint assert while editing');
    final body = jsonDecode(resp.result!) as Map<String, dynamic>;
    expect(body['format'], 'png');
    expect((body['data_base64'] as String).length, greaterThan(100));
  });

  testWidgets('gives a friendly error when no frame has rendered yet (#4)',
      (tester) async {
    // No RepaintBoundary in the tree (pre-first-frame / native splash). The
    // error should explain it and point at a recovery, not leak an internal.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('x'),
      ),
    );
    await tester.pump();

    final resp = await tester.runAsync(
      () => ScreenshotExtension.handle('ext.qa.screenshot', const {}),
    );
    expect(resp!.isError(), isTrue,
        reason: 'no boundary to capture before the first frame');
  });
}
