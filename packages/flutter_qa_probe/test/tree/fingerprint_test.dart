import 'package:flutter_qa_probe/src/tree/fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identical inputs produce identical fingerprints', () {
    final a = Fingerprint.compute(
      creationLocation: 'lib/cart.dart:42:8',
      widgetType: 'ElevatedButton',
      ancestorTypes: ['Scaffold', 'Column'],
      siblingIndex: 0,
      visibleText: 'Checkout',
    );
    final b = Fingerprint.compute(
      creationLocation: 'lib/cart.dart:42:8',
      widgetType: 'ElevatedButton',
      ancestorTypes: ['Scaffold', 'Column'],
      siblingIndex: 0,
      visibleText: 'Checkout',
    );
    expect(a, b);
    expect(a, matches(RegExp(r'^f_[a-f0-9]{12}$')));
  });

  test('different sibling indices produce different fingerprints', () {
    final a = Fingerprint.compute(
      creationLocation: 'lib/cart.dart:42:8',
      widgetType: 'ElevatedButton',
      ancestorTypes: ['Scaffold', 'ListView'],
      siblingIndex: 0,
      visibleText: 'Item',
    );
    final b = Fingerprint.compute(
      creationLocation: 'lib/cart.dart:42:8',
      widgetType: 'ElevatedButton',
      ancestorTypes: ['Scaffold', 'ListView'],
      siblingIndex: 1,
      visibleText: 'Item',
    );
    expect(a, isNot(b));
  });
}
