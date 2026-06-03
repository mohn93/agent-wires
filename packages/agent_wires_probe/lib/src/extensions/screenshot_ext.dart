import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import '../overlay/action_overlay_controller.dart';
import '../overlay/action_overlay_installer.dart';
import '../overlay/overlay_effect.dart';

class ScreenshotExtension {
  static const String name = 'ext.qa.screenshot';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    try {
      // First-call race: the agent may screenshot before the first frame has
      // rasterized (no rootElement yet, or no RepaintBoundary yet). Settle one
      // frame and look again before giving up.
      var boundary = _findVisibleRepaintBoundary();
      if (boundary == null) {
        await _settleFrame();
        boundary = _findVisibleRepaintBoundary();
      }
      if (boundary == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          jsonEncode({
            'error': 'no RepaintBoundary found — no Flutter frame has rendered '
                'yet (still on the native splash / first paint). Retry after '
                'the first frame, e.g. after wait_for_idle.',
          }),
        );
      }
      final image = await captureWithOverlaySuppressed(() => _capture(boundary!));
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          jsonEncode({'error': 'failed to encode PNG'}),
        );
      }
      final b64 = base64Encode(bytes.buffer.asUint8List());
      // After suppression has ended, so the flash is never in the bytes above.
      ActionOverlayController.instance
          .showFlash(kind: OverlayFlashKind.screenshot);
      ActionOverlayInstaller.ensureInstalled();
      return developer.ServiceExtensionResponse.result(jsonEncode({
        'format': 'png',
        'width': image.width,
        'height': image.height,
        'data_base64': b64,
      }));
    } catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// Runs [body] (the rasterization) with the action overlay hidden, so the
  /// human-only overlay never lands in the captured pixels. `toImage`
  /// rasterizes the retained layer tree as-is, so we must commit a frame with
  /// the overlay already painted out *before* capturing — otherwise an effect
  /// still animating from a preceding action (a tap ripple, an inspect
  /// highlight) leaks into the PNG. The wait is bounded so a frameless / wedged
  /// engine can never hang the tool call (the same safety net as
  /// [_settleFrame]). Visibility is always restored, even on failure.
  static Future<T> captureWithOverlaySuppressed<T>(
      Future<T> Function() body) async {
    final c = ActionOverlayController.instance;
    c.beginCaptureSuppression();
    try {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame
          .timeout(const Duration(seconds: 1), onTimeout: () {});
      return await body();
    } finally {
      c.endCaptureSuppression();
    }
  }

  /// Captures the boundary, retrying across settled frames. `toImage` asserts
  /// `!debugNeedsPaint` (debug builds): with a focused TextField the blinking
  /// cursor repaints every frame, so the boundary is perpetually dirty and the
  /// naive single call always threw — a screenshot was impossible exactly while
  /// editing. We try optimistically, and on failure settle a frame (which also
  /// commits the freshest pixels, avoiding a stale capture) and retry, catching
  /// one of the windows between cursor blinks where the boundary is clean (#4).
  static Future<ui.Image> _capture(
    RenderRepaintBoundary boundary, {
    int attempts = 4,
  }) async {
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      try {
        return await boundary.toImage(pixelRatio: 1.0);
      } catch (e) {
        lastError = e;
        if (i < attempts - 1) {
          await _settleFrame();
          boundary = _findVisibleRepaintBoundary() ?? boundary;
        }
      }
    }
    throw lastError ?? StateError('screenshot capture failed');
  }

  /// Schedules a frame and waits for it to commit, so the next capture sees the
  /// latest painted pixels. Bounded so it can never hang the tool call if no
  /// frame is being produced (e.g. a wedged engine, or a non-rendering test
  /// binding) — in a live app a frame lands in ~16ms; the timeout is only a
  /// safety net.
  static Future<void> _settleFrame() async {
    try {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      // Timed out / no frame driver — proceed with whatever we have.
    }
  }

  /// Finds the on-screen content boundary to capture.
  ///
  /// Flutter wraps every Navigator route in its own `RepaintBoundary`
  /// (`_ModalScope`). The naive "first RepaintBoundary in DFS" picks the
  /// *bottom* (oldest) route in the stack — a route that is covered by the
  /// current one, whose retained layer holds whatever it last painted (the
  /// previous screen, or a mid-transition frame). That is the root cause of
  /// the "screenshot is one navigation behind / byte-identical stale frame"
  /// bug (#13), and of the `!debugNeedsPaint` assert firing on a covered route
  /// that the Overlay never repaints.
  ///
  /// A covered route's layer is *detached* from the live scene, while the
  /// visible route's layer is attached. So we pick the largest **attached**
  /// boundary (the full-screen visible route), preferring the outermost on a
  /// tie. We deliberately do not filter on `debugNeedsPaint` here: the visible
  /// route can be transiently dirty (e.g. a blinking text cursor, #4) — that
  /// retry is handled by [_capture].
  static RenderRepaintBoundary? _findVisibleRepaintBoundary() {
    RenderRepaintBoundary? best;
    double bestArea = -1;
    void walk(RenderObject ro) {
      if (ro is RenderRepaintBoundary) {
        // RenderObject.layer is the only way to tell whether this boundary was
        // painted into the live scene (covered routes are detached); there is
        // no public equivalent.
        // ignore: invalid_use_of_protected_member
        final layer = ro.layer;
        if (layer != null && layer.attached) {
          final size = ro.paintBounds.size;
          final area = size.width * size.height;
          if (area > bestArea) {
            bestArea = area;
            best = ro;
          }
        }
      }
      ro.visitChildren(walk);
    }

    final root = WidgetsBinding.instance.rootElement?.renderObject;
    if (root != null) walk(root);
    return best;
  }
}
