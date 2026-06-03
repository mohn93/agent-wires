import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_wires_probe/src/actions/scroll_driver.dart';

/// Pumps [child] and returns the live [ScrollableState] of the named content
/// list so tests can assert it (and only it) moved.
ScrollController _contentController() => ScrollController();

void main() {
  group('scrollAnyVisible skips unusable scrollables', () {
    testWidgets(
      'an offstage (unattached) vertical Scrollable before the content list '
      'does not crash, and the content list scrolls',
      (tester) async {
        final content = _contentController();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                // Offstage => built but never laid out => its ScrollPosition
                // has no dimensions. This is the DevicePreview-style shell that
                // currently makes _drive throw "Null check operator".
                const Offstage(
                  offstage: true,
                  child: SizedBox(
                    height: 200,
                    child: SingleChildScrollView(child: SizedBox(height: 999)),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: content,
                    itemCount: 100,
                    itemBuilder: (_, i) => SizedBox(height: 50, child: Text('row $i')),
                  ),
                ),
              ],
            ),
          ),
        ));

        final ok = await tester.runAsync(
          () => ScrollDriver.scrollAnyVisible(ScrollDir.down, 200),
        );
        await tester.pumpAndSettle();

        expect(ok, isTrue);
        expect(content.position.pixels, greaterThan(0));
      },
    );

    testWidgets(
      'a horizontal Scrollable before the content list is skipped for a '
      'vertical scroll (axis mismatch must not shadow the real list)',
      (tester) async {
        final content = _contentController();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 30,
                    itemBuilder: (_, i) => SizedBox(width: 80, child: Text('h$i')),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: content,
                    itemCount: 100,
                    itemBuilder: (_, i) => SizedBox(height: 50, child: Text('row $i')),
                  ),
                ),
              ],
            ),
          ),
        ));

        final ok = await tester.runAsync(
          () => ScrollDriver.scrollAnyVisible(ScrollDir.down, 200),
        );
        await tester.pumpAndSettle();

        expect(ok, isTrue);
        expect(content.position.pixels, greaterThan(0));
      },
    );
  });

  group('scrollIn resolves the enclosing Scrollable', () {
    testWidgets(
      'passing a leaf row element walks up to its ancestor Scrollable',
      (tester) async {
        final content = _contentController();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              controller: content,
              itemCount: 100,
              itemBuilder: (_, i) => SizedBox(height: 50, child: Text('row $i')),
            ),
          ),
        ));

        // A leaf inside the list — its enclosing Scrollable is an ANCESTOR,
        // not a descendant.
        final rowElement = tester.element(find.text('row 1'));

        final ok = await tester.runAsync(
          () => ScrollDriver.scrollIn(rowElement, ScrollDir.down, 200),
        );
        await tester.pumpAndSettle();

        expect(ok, isTrue);
        expect(content.position.pixels, greaterThan(0));
      },
    );
  });
}
