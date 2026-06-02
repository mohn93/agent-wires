import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_installer.dart';
import 'package:agent_wires_probe/src/overlay/overlay_effect.dart';
import 'package:agent_wires_probe/src/tree/snapshot_builder.dart';
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

  testWidgets(
      'an installed overlay with a full-screen effect does not occlude the app',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('real-content-canary'),
          ),
        ),
      ),
    ));

    // Install the overlay and show a full-screen flash — the worst case for
    // occlusion, since its Stack covers the whole viewport.
    ActionOverlayInstaller.ensureInstalled();
    ActionOverlayController.instance.showFlash(kind: OverlayFlashKind.snapshot);
    await tester.pump();

    final snap = SnapshotBuilder.build();

    // The real button is still in the snapshot (not occluded by the overlay).
    expect(
      snap.elements.any((e) => e.label == 'real-content-canary'),
      isTrue,
      reason: 'the overlay must not occlude real app content',
    );
    // And the overlay itself never leaks into the snapshot.
    expect(
      [...snap.elements, ...snap.unresolved]
          .any((e) => e.widgetType == 'AgentWiresOverlayMarker'),
      isFalse,
    );
    await tester.pumpAndSettle();
  });
}
