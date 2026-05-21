import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/extensions/screenshot_ext.dart';
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
}
