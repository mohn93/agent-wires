import 'package:flutter/widgets.dart';
import 'overlay_effect.dart';

/// Paints a single [OverlayEffect], repainting as its [anim] advances 0→1.
class OverlayEffectPainter extends CustomPainter {
  OverlayEffectPainter(this.effect, this.anim) : super(repaint: anim);
  final OverlayEffect effect;
  final Animation<double> anim;

  static const Color _action = Color(0xFF00E5FF); // touch actions
  static const Color _perception = Color(0xFFFFC107); // look / point-at

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static Color _fade(Color c, double o) =>
      c.withAlpha((255 * o.clamp(0.0, 1.0)).round());

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    switch (effect) {
      case TapEffect(:final point, :final longPress):
        _tap(canvas, point, t, longPress);
      case DragEffect(:final from, :final to):
        _drag(canvas, from, to, t);
      case HighlightEffect(:final bounds, :final label):
        _highlight(canvas, bounds, label, t);
      case FlashEffect(:final kind):
        _flash(canvas, size, kind, t);
    }
  }

  void _tap(Canvas canvas, Offset p, double t, bool longPress) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = _fade(_action, 1 - t);
    canvas.drawCircle(p, _lerp(8, 46, t), ring);
    canvas.drawCircle(p, 8, Paint()..color = _fade(_action, 0.8 * (1 - t)));
    if (longPress) {
      canvas.drawCircle(
          p, _lerp(4, 22, t), Paint()..color = _fade(_action, 0.35 * (1 - t)));
    }
  }

  void _drag(Canvas canvas, Offset from, Offset to, double t) {
    final head = Offset.lerp(from, to, t)!;
    final line = Paint()
      ..color = _fade(_action, 1 - t)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, head, line);
    canvas.drawCircle(head, 6, Paint()..color = _fade(_action, 1 - t));
  }

  void _highlight(Canvas canvas, Rect bounds, String? label, double t) {
    final rrect =
        RRect.fromRectAndRadius(bounds.inflate(2), const Radius.circular(6));
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _fade(_perception, 1 - 0.3 * t));
    canvas.drawRRect(rrect, Paint()..color = _fade(_perception, 0.12 * (1 - t)));
    if (label != null && label.isNotEmpty) {
      _caption(canvas, label, bounds.topLeft, _perception, 1 - t);
    }
  }

  void _flash(Canvas canvas, Size size, OverlayFlashKind kind, double t) {
    final color = kind == OverlayFlashKind.screenshot ? _perception : _action;
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _lerp(10, 2, t)
          ..color = _fade(color, 0.9 * (1 - t)));
    final tag = kind == OverlayFlashKind.screenshot ? 'screenshot' : 'snapshot';
    _caption(canvas, tag, const Offset(8, 8), color, 1 - t);
  }

  void _caption(
      Canvas canvas, String text, Offset at, Color color, double opacity) {
    // Captions narrate the action (a typed string, a widget type); cap the
    // length so a long `enter_text` value can't paint a caption off-screen.
    final label = text.length > 24 ? '${text.substring(0, 23)}…' : text;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 11,
          color: _fade(const Color(0xFF000000), opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = const Offset(4, 2);
    final bg = Rect.fromLTWH(
        at.dx, at.dy, tp.width + pad.dx * 2, tp.height + pad.dy * 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(bg, const Radius.circular(3)),
        Paint()..color = _fade(color, opacity));
    tp.paint(canvas, at + pad);
  }

  @override
  // Repaint is driven by `super(repaint: anim)`; a new painter instance per
  // build always reflects the latest effect, so no extra signal is needed.
  bool shouldRepaint(OverlayEffectPainter old) => false;
}
