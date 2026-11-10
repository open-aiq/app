import 'package:flutter/widgets.dart';

/// The Open AIQ mark: lucide's Wind glyph (https://lucide.dev, ISC license),
/// sized and coloured like an [Icon]. The paths match
/// `docs/src/assets/brand/wind-mark.svg`, so the app, the web and the docs
/// share one mark.
class WindGlyph extends StatelessWidget {
  const WindGlyph({super.key, this.size, this.color, this.semanticLabel});

  /// Defaults to the surrounding [IconTheme] size, then 24.
  final double? size;

  /// Defaults to the surrounding [IconTheme] colour.
  final Color? color;

  /// Read out by screen readers. Without one, the glyph is decorative.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = this.size ?? iconTheme.size ?? 24;
    final glyph = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _WindPainter(
          color ?? iconTheme.color ?? const Color(0xFF000000),
        ),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: glyph);
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(child: glyph),
    );
  }
}

class _WindPainter extends CustomPainter {
  const _WindPainter(this.color);

  final Color color;

  /// Lucide's three gusts in its 24×24 viewBox. SVG's sweep flag 1 is
  /// clockwise on screen, as in Flutter.
  static final Path _gusts = Path()
    // M12.8 19.6 A2 2 0 1 0 14 16 H2
    ..moveTo(12.8, 19.6)
    ..arcToPoint(
      const Offset(14, 16),
      radius: const Radius.circular(2),
      largeArc: true,
      clockwise: false,
    )
    ..lineTo(2, 16)
    // M17.5 8 a2.5 2.5 0 1 1 2 4 H2
    ..moveTo(17.5, 8)
    ..arcToPoint(
      const Offset(19.5, 12),
      radius: const Radius.circular(2.5),
      largeArc: true,
    )
    ..lineTo(2, 12)
    // M9.8 4.4 A2 2 0 1 1 11 8 H2
    ..moveTo(9.8, 4.4)
    ..arcToPoint(
      const Offset(11, 8),
      radius: const Radius.circular(2),
      largeArc: true,
    )
    ..lineTo(2, 8);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      _gusts,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_WindPainter old) => old.color != color;
}
