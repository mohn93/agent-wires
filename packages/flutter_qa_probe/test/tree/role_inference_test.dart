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

  testWidgets('multi-Text card concatenates labels with " · "', (tester) async {
    // The invoice/domain-card pattern: header + value + status, all as
    // sibling Text widgets inside a tappable. The old "first descendant
    // wins" labeled every invoice "Sub Total"; now we get something
    // that distinguishes one card from another.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          onTap: () {},
          child: const Column(
            children: [
              Text('Sub Total'),
              Text('9,709.50 LYD'),
              Text('Unpaid'),
              Text('342844'),
            ],
          ),
        ),
      ),
    ));
    final gd = tester.element(find.byType(GestureDetector));
    final inf = RoleInference.infer(gd);
    expect(inf.label,
        'Sub Total · 9,709.50 LYD · Unpaid · 342844');
    expect(inf.labelSource, LabelSource.textChild);
  });

  testWidgets('single-Text widget still gets a clean label (no separator)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () {}, child: const Text('Submit')),
      ),
    ));
    final btn = tester.element(find.byType(ElevatedButton));
    expect(RoleInference.infer(btn).label, 'Submit');
  });

  testWidgets('label is truncated at 80 chars with ellipsis', (tester) async {
    final long = 'x' * 200;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          onTap: () {},
          child: Text(long),
        ),
      ),
    ));
    final gd = tester.element(find.byType(GestureDetector));
    final inf = RoleInference.infer(gd);
    expect(inf.label!.length, lessThanOrEqualTo(80));
    expect(inf.label!.endsWith('…'), isTrue);
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
