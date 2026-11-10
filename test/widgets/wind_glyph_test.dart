import 'package:app/widgets/wind_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the wind mark paints rounded gusts at the size asked for', (
    tester,
  ) async {
    const sage = Color(0xFF6F7F5C);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: WindGlyph(size: 48, color: sage, semanticLabel: 'Open AIQ'),
        ),
      ),
    );

    final canvas = find.descendant(
      of: find.byType(WindGlyph),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(canvas), const Size.square(48));
    expect(
      canvas,
      paints..path(color: sage, style: PaintingStyle.stroke, strokeWidth: 2),
    );
    expect(find.bySemanticsLabel('Open AIQ'), findsOneWidget);
  });

  testWidgets('the wind mark takes its size and colour from the icon theme', (
    tester,
  ) async {
    const ink = Color(0xFF3B2716);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: IconTheme(
            data: IconThemeData(size: 30, color: ink),
            child: WindGlyph(),
          ),
        ),
      ),
    );

    final canvas = find.descendant(
      of: find.byType(WindGlyph),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(canvas), const Size.square(30));
    expect(canvas, paints..path(color: ink));
  });
}
