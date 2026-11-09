import 'package:app/aqi.dart';
import 'package:app/api/models.dart';
import 'package:app/widgets/ota_badge.dart';
import 'package:app/widgets/tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  test('AQI bands match the web dashboard', () {
    expect(aqiInfo(null).label, 'Unknown');
    expect(aqiInfo(0).label, 'Good');
    expect(aqiInfo(50).label, 'Good');
    expect(aqiInfo(51).label, 'Moderate');
    expect(aqiInfo(150).label, 'Slightly Unhealthy');
    expect(aqiInfo(201).label, 'Very Unhealthy');
    expect(aqiInfo(301).label, 'Hazardous');
    expect(aqiInfo(double.nan).label, 'Unknown');
  });

  testWidgets('AQI tile always shows the band label', (tester) async {
    await tester.pumpWidget(_wrap(const AqiTile(aqi: 57)));
    expect(find.text('57'), findsOneWidget);
    expect(find.text('Moderate'), findsOneWidget);
  });

  testWidgets(
    'OTA badge shows pending update and progress, hides when up to date',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          OtaBadge(
            summary: const OtaSummary(
              status: 'update_available',
              version: '0.2.0',
            ),
            onTap: () => tapped = true,
          ),
        ),
      );
      expect(find.text('Update available'), findsOneWidget);
      await tester.tap(find.text('Update available'));
      expect(tapped, isTrue);

      await tester.pumpWidget(
        _wrap(
          const OtaBadge(
            summary: OtaSummary(status: 'downloading', progress: 40),
          ),
        ),
      );
      expect(find.text('Updating 40%'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(const OtaBadge(summary: OtaSummary(status: 'up_to_date'))),
      );
      expect(find.byType(Container), findsNothing);
    },
  );
}
