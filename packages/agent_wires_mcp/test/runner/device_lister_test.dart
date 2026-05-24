import 'package:agent_wires_mcp/src/runner/device_lister.dart';
import 'package:test/test.dart';

void main() {
  test('parse returns one DeviceInfo per JSON entry, dropping empties', () {
    const sample = '''
[
  {
    "name": "iPhone 17 Pro Max",
    "id": "B89DBF36-947C-40D8-8D19-C3644998607E",
    "isSupported": true,
    "targetPlatform": "ios",
    "emulator": true,
    "sdk": "com.apple.CoreSimulator.SimRuntime.iOS-26-4"
  },
  {
    "name": "macOS",
    "id": "macos",
    "isSupported": true,
    "targetPlatform": "darwin",
    "emulator": false,
    "sdk": "macOS 26.2"
  }
]
''';
    final devices = DeviceLister.parse(sample);
    expect(devices.length, 2);

    final sim = devices.first;
    expect(sim.id, 'B89DBF36-947C-40D8-8D19-C3644998607E');
    expect(sim.name, 'iPhone 17 Pro Max');
    expect(sim.platform, 'ios');
    expect(sim.isEmulator, isTrue);
    expect(sim.isSupported, isTrue);
    expect(sim.sdk, isNotNull);

    expect(devices[1].id, 'macos');
    expect(devices[1].isEmulator, isFalse);
  });

  test('parse tolerates leading log lines before the JSON array', () {
    // flutter sometimes prefixes machine output with a "downloading SDK..."
    // line. Parser skips until the first '['.
    const sample = '''
Downloading Material fonts...                                       3.4s
[
  {"id":"chrome","name":"Chrome","targetPlatform":"web-javascript","emulator":false,"isSupported":true}
]
''';
    expect(DeviceLister.parse(sample).single.id, 'chrome');
  });

  test('parse returns empty list on empty/garbage input', () {
    expect(DeviceLister.parse(''), isEmpty);
    expect(DeviceLister.parse('not json'), isEmpty);
    expect(DeviceLister.parse('[]'), isEmpty);
  });
}
