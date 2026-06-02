import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/overlay/overlay_marker.dart';
import 'package:agent_wires_probe/src/tree/walker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the overlay subtree is excluded from the walk', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Text('app-content'),
            AgentWiresOverlayMarker(child: Text('aw-overlay-canary')),
          ],
        ),
      ),
    ));
    final nodes = ElementTreeWalker.walkFromRoot();
    expect(nodes.any((n) => n.visibleText == 'app-content'), isTrue);
    expect(nodes.any((n) => n.visibleText == 'aw-overlay-canary'), isFalse);
    expect(
        nodes.any((n) => n.widgetType == 'AgentWiresOverlayMarker'), isFalse);
  });
}
