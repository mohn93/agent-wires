import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_probe/src/extensions/scroll_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scroll down moves the ScrollPosition', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
        ),
      ),
    ));

    final resp = await tester.runAsync(() async {
      return ScrollExtension.handle('ext.qa.scroll', {
        'direction': 'down',
        'distance': '200',
      });
    });
    await tester.pumpAndSettle();

    final body = jsonDecode(resp!.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(controller.position.pixels, greaterThan(0));
  });
}
