import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/actions/text_input_driver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('setText replaces the contents of a TextField', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(controller: controller)),
    ));

    final field = tester.element(find.byType(TextField));
    await TextInputDriver.setText(field, 'hello world');
    await tester.pumpAndSettle();

    expect(controller.text, 'hello world');
  });
}
