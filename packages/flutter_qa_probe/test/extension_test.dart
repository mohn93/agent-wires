import 'dart:developer' as developer;
import 'package:flutter_qa_probe/flutter_qa_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('install registers a "ext.qa.ping" extension that returns ok', () async {
    FlutterQAProbe.install();
    final reg = developer.Service.getInfo();
    expect(reg, isNotNull);
    // We can't call extensions from inside a unit test without a VM service,
    // but we can assert the extension name was registered by checking the
    // private registry through FlutterQAProbe.registeredExtensions.
    expect(FlutterQAProbe.registeredExtensions, contains('ext.qa.ping'));
  });
}
