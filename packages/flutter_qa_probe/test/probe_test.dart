import 'package:flutter_qa_probe/flutter_qa_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FlutterQAProbe.install is a no-op when called twice', () {
    FlutterQAProbe.install();
    FlutterQAProbe.install();
    expect(FlutterQAProbe.isInstalled, isTrue);
  });
}
