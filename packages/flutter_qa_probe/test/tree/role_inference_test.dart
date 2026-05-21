import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/tree/role_inference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('button with Text child gets label from text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () {}, child: const Text('Checkout')),
      ),
    ));
    final button = tester.element(find.byType(ElevatedButton));
    final inf = RoleInference.infer(button);
    expect(inf.label, 'Checkout');
    expect(inf.role, 'button');
    expect(inf.labelSource, LabelSource.textChild);
  });

  testWidgets('IconButton with cart icon and no text gets role "cart"', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IconButton(
          onPressed: () {},
          icon: const Icon(Icons.shopping_cart),
        ),
      ),
    ));
    final btn = tester.element(find.byType(IconButton));
    final inf = RoleInference.infer(btn);
    expect(inf.label, 'cart');
    expect(inf.role, 'button');
    expect(inf.labelSource, LabelSource.icon);
  });
}
