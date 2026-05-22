import 'package:flutter_probe/src/tree/classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ElevatedButton is promoted', () {
    expect(Classifier.classifyByType('ElevatedButton'), Classification.promote);
  });
  test('Padding is skipped', () {
    expect(Classifier.classifyByType('Padding'), Classification.skip);
  });
  test('Text is collapsed into parent', () {
    expect(Classifier.classifyByType('Text'), Classification.collapse);
  });
  test('Unknown widgets default to skip', () {
    expect(Classifier.classifyByType('SomeRandomCustomWidget'), Classification.skip);
  });
}
