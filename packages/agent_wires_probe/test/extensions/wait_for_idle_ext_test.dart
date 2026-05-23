import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/wait_for_idle_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wait_for_idle returns success:true on a static screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('static'))));
    await tester.pumpAndSettle();

    final resp = await tester.runAsync(() async {
      return WaitForIdleExtension.handle('ext.qa.wait_for_idle', const {});
    });
    final body = jsonDecode(resp!.result!) as Map<String, dynamic>;
    expect(body['success'], isTrue);
    expect(body['idle'], isTrue);
  });
}
