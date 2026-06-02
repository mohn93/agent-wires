import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_installer.dart';
import 'package:agent_wires_probe/src/overlay/overlay_marker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    ActionOverlayController.instance.reset();
    ActionOverlayInstaller.reset();
  });
  tearDown(() {
    ActionOverlayController.instance.reset();
    ActionOverlayInstaller.reset();
  });

  testWidgets('inserts the host into a MaterialApp overlay', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    expect(ActionOverlayInstaller.ensureInstalled(), isTrue);
    await tester.pump();
    expect(find.byType(AgentWiresOverlayMarker), findsOneWidget);
  });

  testWidgets('is idempotent — calling twice inserts one host', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    ActionOverlayInstaller.ensureInstalled();
    ActionOverlayInstaller.ensureInstalled();
    await tester.pump();
    expect(find.byType(AgentWiresOverlayMarker), findsOneWidget);
  });

  testWidgets('no Overlay present → returns false, does not throw',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Text('no overlay here'),
    ));
    expect(ActionOverlayInstaller.ensureInstalled(), isFalse);
    await tester.pump();
    expect(find.byType(AgentWiresOverlayMarker), findsNothing);
  });
}
