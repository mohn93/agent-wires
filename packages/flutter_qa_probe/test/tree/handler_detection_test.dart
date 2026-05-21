import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/src/tree/classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GestureDetector with onTap is promoted', () {
    final w = GestureDetector(onTap: () {}, child: const SizedBox());
    expect(Classifier.classify(w), Classification.promote);
  });
  test('GestureDetector without handlers is skipped', () {
    final w = GestureDetector(child: const SizedBox());
    expect(Classifier.classify(w), Classification.skip);
  });
  test('InkWell with onTap is promoted', () {
    final w = InkWell(onTap: () {}, child: const SizedBox());
    expect(Classifier.classify(w), Classification.promote);
  });
}
