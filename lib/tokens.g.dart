// Generated from docs/src/data/tokens.json by `make tokens:sync` in docs/. Don't edit.

import 'package:flutter/widgets.dart';

/// Material 3 color roles for one brightness.
@immutable
class AiqSchemeTokens {
  const AiqSchemeTokens({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.outline,
    required this.outlineVariant,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color error;
  final Color onError;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color outline;
  final Color outlineVariant;

  static const light = AiqSchemeTokens(
    primary: Color(0xFF8A5D3B),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFF1E6D6),
    onPrimaryContainer: Color(0xFF3B2716),
    secondary: Color(0xFF6F7F5C),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE1E7D6),
    onSecondaryContainer: Color(0xFF2F3A24),
    tertiary: Color(0xFF8A6418),
    tertiaryContainer: Color(0xFFFBE7BE),
    onTertiaryContainer: Color(0xFF3F2E05),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFFBF8F3),
    onSurface: Color(0xFF3B2716),
    onSurfaceVariant: Color(0xFF6B5A49),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F1E8),
    surfaceContainer: Color(0xFFF3EBDF),
    surfaceContainerHigh: Color(0xFFEFE5D6),
    surfaceContainerHighest: Color(0xFFEADFCD),
    outline: Color(0xFFB3926B),
    outlineVariant: Color(0xFFE6D9C6),
  );

  static const dark = AiqSchemeTokens(
    primary: Color(0xFFD6B88F),
    onPrimary: Color(0xFF3B2716),
    primaryContainer: Color(0xFF4A3826),
    onPrimaryContainer: Color(0xFFF1E6D6),
    secondary: Color(0xFFA3B18A),
    onSecondary: Color(0xFF1F2716),
    secondaryContainer: Color(0xFF3A4430),
    onSecondaryContainer: Color(0xFFE1E7D6),
    tertiary: Color(0xFFF2C46D),
    tertiaryContainer: Color(0xFF4D3B12),
    onTertiaryContainer: Color(0xFFFBE7BE),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    surface: Color(0xFF1B1611),
    onSurface: Color(0xFFF4E9DA),
    onSurfaceVariant: Color(0xFFCDBCA5),
    surfaceContainerLowest: Color(0xFF15110D),
    surfaceContainerLow: Color(0xFF211B15),
    surfaceContainer: Color(0xFF261F18),
    surfaceContainerHigh: Color(0xFF2E261D),
    surfaceContainerHighest: Color(0xFF372D23),
    outline: Color(0xFF8A6A48),
    outlineVariant: Color(0xFF3F3327),
  );
}

/// Brand and illustration colors, light mode.
abstract final class AiqBrandLight {
  static const accent = Color(0xFF8A5D3B);
  static const sage = Color(0xFF6F7F5C);
  static const ink = Color(0xFF3B2716);
  static const sand = Color(0xFFF1E6D6);
  static const wood = Color(0xFFC9A77C);
  static const highlight = Color(0xFFF2C46D);
  static const ground = Color(0x1A8A5D3B);
  static const shadow = Color(0x143B2716);
  static const online = Color(0xFF5F7A3F);
}

/// Brand and illustration colors, dark mode.
abstract final class AiqBrandDark {
  static const accent = Color(0xFFD6B88F);
  static const sage = Color(0xFFA3B18A);
  static const ink = Color(0xFFF4E9DA);
  static const sand = Color(0xFF3A2C1F);
  static const wood = Color(0xFF8A6A48);
  static const highlight = Color(0xFFF2C46D);
  static const ground = Color(0x24D6B88F);
  static const shadow = Color(0x40000000);
  static const online = Color(0xFFA3B18A);
}

/// Corner radii in logical pixels.
abstract final class AiqRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double card = 24;
  static const double sheet = 28;
}

/// Motion timings. Every animation stops under reduced motion.
abstract final class AiqMotion {
  static const resize = Duration(milliseconds: 300);
  static const lift = Duration(milliseconds: 500);
  static const fade = Duration(milliseconds: 700);
  static const chart = Duration(milliseconds: 800);
  static const pulse = Duration(milliseconds: 1400);
  static const float = Duration(milliseconds: 7000);
  static const calm = Cubic(0.22, 0.61, 0.36, 1);
  static const double floatDistance = 4;
}

/// One US EPA AQI band. [max] is null for the open-ended top band.
typedef AiqBandToken = ({
  int? max,
  String label,
  String short,
  Color background,
  Color foreground,
});

const aiqBands = <AiqBandToken>[
  (
    max: 50,
    label: 'Good',
    short: 'Good',
    background: Color(0xFFA8E05F),
    foreground: Color(0xFF718B3A),
  ),
  (
    max: 100,
    label: 'Moderate',
    short: 'Moderate',
    background: Color(0xFFFDD64B),
    foreground: Color(0xFFA57F23),
  ),
  (
    max: 150,
    label: 'Slightly Unhealthy',
    short: 'Slightly Unhealthy',
    background: Color(0xFFFF9B57),
    foreground: Color(0xFFB25826),
  ),
  (
    max: 200,
    label: 'Unhealthy',
    short: 'Unhealthy',
    background: Color(0xFFFE6A69),
    foreground: Color(0xFFAF2C3B),
  ),
  (
    max: 300,
    label: 'Very Unhealthy',
    short: 'Very Unhealthy',
    background: Color(0xFFA97ABC),
    foreground: Color(0xFF634675),
  ),
  (
    max: null,
    label: 'Hazardous',
    short: 'Hazardous',
    background: Color(0xFFA87383),
    foreground: Color(0xFF683E51),
  ),
];

const aiqUnknownBand = (
  max: null,
  label: 'Unknown',
  short: 'No data',
  background: Color(0xFFE5E5E5),
  foreground: Color(0xFF525252),
);
