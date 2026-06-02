import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'overlay_effect.dart';

/// Widget-free model holding the active on-screen effects. A process-global
/// singleton so static service-extension handlers can push to it without
/// threading a reference through every call. The host widget listens and
/// renders; the screenshot/snapshot paths read [suppressedForCapture] and
/// [visibleEffects] to keep the overlay out of the agent's perception.
class ActionOverlayController extends ChangeNotifier {
  ActionOverlayController._();
  static final ActionOverlayController instance = ActionOverlayController._();

  /// Most effects kept at once; a burst of actions cannot grow unbounded.
  static const int maxEffects = 12;

  bool _enabled = true;
  bool get enabled => _enabled;

  bool _suppressed = false;
  bool get suppressedForCapture => _suppressed;

  final List<OverlayEffect> _effects = <OverlayEffect>[];
  List<OverlayEffect> get effects => List.unmodifiable(_effects);

  /// The effects the host should paint right now — empty while a screenshot is
  /// being captured, so the overlay never lands in the captured pixels.
  List<OverlayEffect> get visibleEffects =>
      _suppressed ? const <OverlayEffect>[] : List.unmodifiable(_effects);

  int _seq = 0;
  String _nextId() => 'fx_${_seq++}';

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) _effects.clear();
    notifyListeners();
  }

  void beginCaptureSuppression() {
    if (_suppressed) return;
    _suppressed = true;
    notifyListeners();
  }

  void endCaptureSuppression() {
    if (!_suppressed) return;
    _suppressed = false;
    notifyListeners();
  }

  void showTap(Offset point, {bool longPress = false}) =>
      _add(TapEffect(id: _nextId(), point: point, longPress: longPress));

  void showDrag(Offset from, Offset to) =>
      _add(DragEffect(id: _nextId(), from: from, to: to));

  void showHighlight(Rect bounds, {String? label}) =>
      _add(HighlightEffect(id: _nextId(), bounds: bounds, label: label));

  void showFlash({required OverlayFlashKind kind}) =>
      _add(FlashEffect(id: _nextId(), kind: kind));

  void removeEffect(OverlayEffect effect) {
    if (_effects.remove(effect)) notifyListeners();
  }

  void _add(OverlayEffect effect) {
    if (!_enabled) return;
    _effects.add(effect);
    while (_effects.length > maxEffects) {
      _effects.removeAt(0);
    }
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _enabled = true;
    _suppressed = false;
    _effects.clear();
    _seq = 0;
    notifyListeners();
  }
}
