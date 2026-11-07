import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

/// Sand & Sage: the visual style shared with the docs site (see AGENTS.md).
/// Warm camel and sand with sage, soft rounded surfaces, and dark values
/// that are chosen rather than inverted.
@immutable
class AiqPalette extends ThemeExtension<AiqPalette> {
  const AiqPalette({
    required this.accent,
    required this.sage,
    required this.ink,
    required this.sand,
    required this.wood,
    required this.highlight,
    required this.ground,
    required this.shadow,
  });

  /// Camel accent: `#8a5d3b`, dark `#d6b88f`.
  final Color accent;

  /// Sage: `#6f7f5c`, dark `#a3b18a`. Screens in illustrations.
  final Color sage;

  /// Illustration ink: `#3b2716`.
  final Color ink;

  /// Illustration fill: `#f1e6d6`.
  final Color sand;

  /// Illustration outline: `#c9a77c`.
  final Color wood;

  /// The one warm highlight, for lights and sparks: `#f2c46d`.
  final Color highlight;

  /// Soft tinted ground under illustrations, instead of a drop shadow.
  final Color ground;

  /// Warm-tinted resting shadow for raised cards.
  final Color shadow;

  static const light = AiqPalette(
    accent: Color(0xFF8A5D3B),
    sage: Color(0xFF6F7F5C),
    ink: Color(0xFF3B2716),
    sand: Color(0xFFF1E6D6),
    wood: Color(0xFFC9A77C),
    highlight: Color(0xFFF2C46D),
    ground: Color(0x1A8A5D3B),
    shadow: Color(0x143B2716),
  );

  static const dark = AiqPalette(
    accent: Color(0xFFD6B88F),
    sage: Color(0xFFA3B18A),
    ink: Color(0xFFF4E9DA),
    sand: Color(0xFF3A2C1F),
    wood: Color(0xFF8A6A48),
    highlight: Color(0xFFF2C46D),
    ground: Color(0x24D6B88F),
    shadow: Color(0x40000000),
  );

  static AiqPalette of(BuildContext context) =>
      Theme.of(context).extension<AiqPalette>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  AiqPalette copyWith({
    Color? accent,
    Color? sage,
    Color? ink,
    Color? sand,
    Color? wood,
    Color? highlight,
    Color? ground,
    Color? shadow,
  }) => AiqPalette(
    accent: accent ?? this.accent,
    sage: sage ?? this.sage,
    ink: ink ?? this.ink,
    sand: sand ?? this.sand,
    wood: wood ?? this.wood,
    highlight: highlight ?? this.highlight,
    ground: ground ?? this.ground,
    shadow: shadow ?? this.shadow,
  );

  @override
  AiqPalette lerp(AiqPalette? other, double t) {
    if (other == null) return this;
    return AiqPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      sand: Color.lerp(sand, other.sand, t)!,
      wood: Color.lerp(wood, other.wood, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      ground: Color.lerp(ground, other.ground, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// Raised cards sit lighter than the page: white on sand in light mode, one
/// step brighter than the page in dark mode.
Color raisedSurface(ColorScheme scheme) => scheme.brightness == Brightness.dark
    ? scheme.surfaceContainer
    : scheme.surfaceContainerLowest;

/// Large radius for raised cards (`1.5rem` on the docs site).
const cardRadius = 24.0;

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? AiqPalette.dark : AiqPalette.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: brightness,
      ).copyWith(
        primary: palette.accent,
        onPrimary: dark ? const Color(0xFF3B2716) : Colors.white,
        primaryContainer: dark
            ? const Color(0xFF4A3826)
            : const Color(0xFFF1E6D6),
        onPrimaryContainer: dark
            ? const Color(0xFFF1E6D6)
            : const Color(0xFF3B2716),
        secondary: palette.sage,
        onSecondary: dark ? const Color(0xFF1F2716) : Colors.white,
        secondaryContainer: dark
            ? const Color(0xFF3A4430)
            : const Color(0xFFE1E7D6),
        onSecondaryContainer: dark
            ? const Color(0xFFE1E7D6)
            : const Color(0xFF2F3A24),
        tertiary: dark ? const Color(0xFFF2C46D) : const Color(0xFF8A6418),
        tertiaryContainer: dark
            ? const Color(0xFF4D3B12)
            : const Color(0xFFFBE7BE),
        onTertiaryContainer: dark
            ? const Color(0xFFFBE7BE)
            : const Color(0xFF3F2E05),
        surface: dark ? const Color(0xFF1B1611) : const Color(0xFFFBF8F3),
        onSurface: dark ? const Color(0xFFF4E9DA) : const Color(0xFF3B2716),
        onSurfaceVariant: dark
            ? const Color(0xFFCDBCA5)
            : const Color(0xFF6B5A49),
        surfaceContainerLowest: dark ? const Color(0xFF15110D) : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xFF211B15)
            : const Color(0xFFF7F1E8),
        surfaceContainer: dark
            ? const Color(0xFF261F18)
            : const Color(0xFFF3EBDF),
        surfaceContainerHigh: dark
            ? const Color(0xFF2E261D)
            : const Color(0xFFEFE5D6),
        surfaceContainerHighest: dark
            ? const Color(0xFF372D23)
            : const Color(0xFFEADFCD),
        outline: dark ? const Color(0xFF8A6A48) : const Color(0xFFB3926B),
        outlineVariant: dark
            ? const Color(0xFF3F3327)
            : const Color(0xFFE6D9C6),
        surfaceTint: Colors.transparent,
      );

  final rounded16 = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  // Typography that follows the platform font; app bar titles build on it.
  final textTheme = ThemeData(brightness: brightness, useMaterial3: true)
      .textTheme
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  return ThemeData(
    textTheme: textTheme,
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: raisedSurface(scheme),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      elevation: 0,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      highlightElevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    listTileTheme: ListTileThemeData(shape: rounded16),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: rounded16,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    extensions: [
      palette,
      // Match Clerk's sign-in widgets to the app instead of Clerk's default
      // black/purple palette. `background` equals the page colour and
      // `altBackground` (Clerk's card shadow) does too, so the card blends into
      // the page. Clerk paints primary button text in `background`, so it must
      // contrast with `accent`.
      ClerkThemeExtension(
        colors: ClerkThemeColors(
          background: scheme.surface,
          altBackground: scheme.surface,
          borderSide: scheme.outlineVariant,
          text: scheme.onSurface,
          icon: scheme.onSurfaceVariant,
          lightweightText: scheme.onSurfaceVariant,
          error: scheme.error,
          accent: scheme.primary,
        ),
      ),
    ],
  );
}
