import 'package:flutter/widgets.dart';
import 'action_overlay_controller.dart';
import 'action_overlay_host.dart';

/// Lazily inserts the single [ActionOverlayHost] into the app's topmost
/// [Overlay]. Idempotent and structure-independent: if no Overlay exists yet
/// (before the first frame, or an app with no Navigator) it returns false and
/// a later call retries.
class ActionOverlayInstaller {
  static OverlayEntry? _entry;

  static bool ensureInstalled() {
    if (_entry != null) return true;
    final overlay = _findOverlayState();
    if (overlay == null) return false;
    final entry = OverlayEntry(
      builder: (_) =>
          ActionOverlayHost(controller: ActionOverlayController.instance),
    );
    overlay.insert(entry);
    _entry = entry;
    return true;
  }

  static OverlayState? _findOverlayState() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    OverlayState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is OverlayState) {
        found = e.state as OverlayState;
        return;
      }
      e.visitChildren(visit);
    }
    visit(root);
    return found;
  }

  @visibleForTesting
  static void reset() {
    _entry?.remove();
    _entry = null;
  }
}
