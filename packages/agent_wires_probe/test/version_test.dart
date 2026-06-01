import 'dart:io';

import 'package:agent_wires_probe/agent_wires_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probeVersion stays in sync with pubspec.yaml (#6 version skew)', () {
    // The MCP server warns on probe/server skew using the version the probe
    // reports over ext.qa.ping. If this constant drifts from the published
    // package version, that warning lies — so pin them together.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(probeVersion, match!.group(1)!.trim());
  });
}
