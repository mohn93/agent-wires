import 'package:flutter_probe/flutter_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FlutterProbe.install is a no-op when called twice', () {
    FlutterProbe.install();
    FlutterProbe.install();
    expect(FlutterProbe.isInstalled, isTrue);
  });
}
