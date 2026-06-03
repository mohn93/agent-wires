import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:agent_wires_probe/src/extensions/screenshot_ext.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decodes the handler's base64 PNG and returns the centre pixel colour.
Future<Color> _centrePixel(String b64) async {
  final codec = await ui.instantiateImageCodec(base64Decode(b64));
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final x = img.width ~/ 2, y = img.height ~/ 2;
  final o = (y * img.width + x) * 4;
  return Color.fromARGB(
    data.getUint8(o + 3),
    data.getUint8(o),
    data.getUint8(o + 1),
    data.getUint8(o + 2),
  );
}

void main() {
  testWidgets(
    'screenshot captures the visible TOP route, not the covered bottom one (#13)',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: const ColoredBox(color: Color(0xFFFF0000)), // red home
      ));
      await tester.pump();

      // Push an opaque route that fully covers the home route. Flutter wraps
      // each route in its own RepaintBoundary; the covered home route's
      // boundary is the FIRST in DFS and retains its last-painted (red) layer.
      nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const ColoredBox(color: Color(0xFF0000FF)), // blue
      ));
      await tester.pumpAndSettle();

      final colour = await tester.runAsync(() async {
        final resp =
            await ScreenshotExtension.handle('ext.qa.screenshot', const {});
        expect(resp.isError(), isFalse,
            reason: 'capture must succeed on a normal navigated screen');
        final body = jsonDecode(resp.result!) as Map<String, dynamic>;
        return _centrePixel(body['data_base64'] as String);
      });

      // Must be the blue top route, not the stale red bottom route.
      // Channels are 0.0–1.0 doubles.
      expect(colour!.b, greaterThan(0.8),
          reason: 'expected the visible (blue) top route');
      expect(colour.r, lessThan(0.25),
          reason: 'red bottom route leaked → captured the wrong boundary');
    },
  );
}
