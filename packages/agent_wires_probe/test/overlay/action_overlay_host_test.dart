import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_controller.dart';
import 'package:agent_wires_probe/src/overlay/action_overlay_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = ActionOverlayController.instance;
  setUp(c.reset);
  tearDown(c.reset);

  Widget host() => Directionality(
        textDirection: TextDirection.ltr,
        child: ActionOverlayHost(controller: c),
      );

  testWidgets('renders one keyed effect per active effect', (tester) async {
    await tester.pumpWidget(host());
    c.showTap(const Offset(20, 20));
    await tester.pump(); // let the host rebuild
    expect(find.byKey(const ValueKey('aw_effect_fx_0')), findsOneWidget);
  });

  testWidgets('effect is removed after its animation completes',
      (tester) async {
    await tester.pumpWidget(host());
    c.showTap(const Offset(20, 20));
    await tester.pump();
    expect(c.effects, isNotEmpty);
    await tester.pumpAndSettle(); // drain the 600ms animation
    expect(c.effects, isEmpty);
  });

  testWidgets('renders nothing while suppressed', (tester) async {
    await tester.pumpWidget(host());
    c.showTap(const Offset(20, 20));
    c.beginCaptureSuppression();
    await tester.pump();
    expect(find.byKey(const ValueKey('aw_effect_fx_0')), findsNothing);
    c.endCaptureSuppression();
    await tester.pumpAndSettle();
  });

  testWidgets('IgnorePointer lets a widget beneath still receive taps',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
          ActionOverlayHost(controller: c),
        ],
      ),
    ));
    c.showTap(const Offset(20, 20));
    await tester.pump();
    await tester.tapAt(const Offset(50, 50));
    expect(taps, 1);
    await tester.pumpAndSettle();
  });
}
