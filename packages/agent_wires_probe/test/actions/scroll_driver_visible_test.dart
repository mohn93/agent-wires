import 'package:agent_wires_probe/src/actions/scroll_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'scrollAnyVisible drives the list on the visible route, not the '
      'larger one buried under it', (tester) async {
    final under = ScrollController();
    final top = ScrollController();
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return Scaffold(
          body: ListView.builder(
            controller: under,
            itemCount: 100,
            itemBuilder: (_, i) => SizedBox(height: 50, child: Text('u$i')),
          ),
        );
      }),
    ));
    Navigator.of(ctx).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: Column(children: [
          SizedBox(
            height: 300,
            child: ListView.builder(
              controller: top,
              itemCount: 100,
              itemBuilder: (_, i) => SizedBox(height: 50, child: Text('t$i')),
            ),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    final ok = await ScrollDriver.scrollAnyVisible(ScrollDir.down, 200);
    await tester.pumpAndSettle();

    expect(ok, isTrue);
    expect(top.position.pixels, greaterThan(0),
        reason: 'the on-screen list must be the one scrolled');
    expect(under.position.pixels, 0,
        reason: 'the covered route must be left alone');
  });

  testWidgets(
      'scrollAnyVisible refuses to scroll a list hidden under a route that '
      'has no scrollable of its own', (tester) async {
    final under = ScrollController();
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return Scaffold(
          body: ListView.builder(
            controller: under,
            itemCount: 100,
            itemBuilder: (_, i) => SizedBox(height: 50, child: Text('u$i')),
          ),
        );
      }),
    ));
    Navigator.of(ctx).push(MaterialPageRoute<void>(
      builder: (_) =>
          const Scaffold(body: Center(child: Text('no list here'))),
    ));
    await tester.pumpAndSettle();

    final ok = await ScrollDriver.scrollAnyVisible(ScrollDir.down, 200);
    await tester.pumpAndSettle();

    expect(ok, isFalse, reason: 'nothing visible to scroll must be reported');
    expect(under.position.pixels, 0);
  });
}
