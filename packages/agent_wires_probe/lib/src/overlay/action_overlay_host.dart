import 'package:flutter/widgets.dart';
import 'action_overlay_controller.dart';
import 'overlay_marker.dart';
import 'overlay_painters.dart';

/// Renders the active overlay effects above the app. Wrapped in
/// [AgentWiresOverlayMarker] (so snapshot skips it) and [IgnorePointer] (so it
/// never steals input). Owns one [AnimationController] per effect and removes
/// each effect from the controller when its animation completes.
class ActionOverlayHost extends StatefulWidget {
  const ActionOverlayHost({super.key, required this.controller});
  final ActionOverlayController controller;
  @override
  State<ActionOverlayHost> createState() => _ActionOverlayHostState();
}

class _ActionOverlayHostState extends State<ActionOverlayHost>
    with TickerProviderStateMixin {
  final Map<String, AnimationController> _anims = {};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _sync();
  }

  void _onChange() {
    if (!mounted) return;
    setState(_sync);
  }

  void _sync() {
    for (final fx in widget.controller.effects) {
      _anims.putIfAbsent(fx.id, () {
        final ac = AnimationController(vsync: this, duration: fx.duration)
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed) {
              widget.controller.removeEffect(fx);
            }
          });
        ac.forward();
        return ac;
      });
    }
    final live = widget.controller.effects.map((e) => e.id).toSet();
    for (final id in _anims.keys.where((k) => !live.contains(k)).toList()) {
      _anims.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    for (final ac in _anims.values) {
      ac.dispose();
    }
    _anims.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AgentWiresOverlayMarker(
      child: IgnorePointer(
        child: Stack(
          children: [
            for (final fx in widget.controller.visibleEffects)
              if (_anims[fx.id] != null)
                Positioned.fill(
                  key: ValueKey('aw_effect_${fx.id}'),
                  child: CustomPaint(
                    painter: OverlayEffectPainter(fx, _anims[fx.id]!),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
