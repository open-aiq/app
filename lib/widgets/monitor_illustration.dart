import 'package:flutter/material.dart';

import '../theme.dart';

/// The friendly air monitor from the docs: a sand body with a wood outline,
/// a sage screen with a smiling face, and a soft ground shadow. It floats
/// about 4px over 7s and its status light glows gently; both hold still when
/// the system asks for reduced motion.
///
/// Decorative: screen readers skip it, so say what matters in nearby text.
class MonitorIllustration extends StatefulWidget {
  const MonitorIllustration({super.key, this.size = 140});

  /// Width in logical pixels; the height follows the 6:5 drawing.
  final double size;

  @override
  State<MonitorIllustration> createState() => _MonitorIllustrationState();
}

class _MonitorIllustrationState extends State<MonitorIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion
        ..stop()
        ..value = 0.5;
    } else if (!_motion.isAnimating) {
      _motion.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AiqPalette.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.size,
        height: widget.size * 5 / 6,
        child: AnimatedBuilder(
          animation: _motion,
          builder: (context, _) => CustomPaint(
            painter: _MonitorPainter(
              palette: palette,
              phase: Curves.easeInOut.transform(_motion.value),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonitorPainter extends CustomPainter {
  _MonitorPainter({required this.palette, required this.phase});

  final AiqPalette palette;

  /// 0..1 through one float; drives the lift and the light's glow.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 120 x 100 grid, scaled to fit.
    canvas.scale(size.width / 120, size.height / 100);

    final lift = -4 * phase;
    final groundScale = 1 - 0.08 * phase;
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(60, 90),
        width: 88 * groundScale,
        height: 10 * groundScale,
      ),
      Paint()..color = palette.ground,
    );

    canvas.save();
    canvas.translate(0, lift);

    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(26, 24, 68, 56),
      const Radius.circular(16),
    );
    canvas.drawRRect(body, Paint()..color = palette.sand);
    canvas.drawRRect(
      body,
      Paint()
        ..color = palette.wood
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(36, 34, 48, 28),
        const Radius.circular(8),
      ),
      Paint()..color = palette.sage,
    );

    final face = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(52, 45), 2.4, face);
    canvas.drawCircle(const Offset(68, 45), 2.4, face);
    canvas.drawPath(
      Path()
        ..moveTo(52, 52)
        ..quadraticBezierTo(60, 58, 68, 52),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // Status light, glowing between 35% and 100%.
    canvas.drawCircle(
      const Offset(84, 71),
      2.6,
      Paint()..color = palette.highlight.withValues(alpha: 0.35 + 0.65 * phase),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MonitorPainter old) =>
      old.phase != phase || old.palette != palette;
}

/// A small line drawing of the monitor, sized and coloured like an [Icon].
/// Used where the app means "your air monitor", such as the Add button.
class MonitorGlyph extends StatelessWidget {
  const MonitorGlyph({super.key, this.size, this.color, this.semanticLabel});

  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = this.size ?? iconTheme.size ?? 24;
    final glyph = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GlyphPainter(color ?? iconTheme.color ?? Colors.black),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: glyph);
    return Semantics(label: semanticLabel, child: glyph);
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 4.5, 18, 15),
        const Radius.circular(4.5),
      ),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6.5, 7.5, 11, 6.5),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
    canvas.drawCircle(const Offset(16.5, 16.8), 1.1, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.color != color;
}
