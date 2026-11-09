import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import 'tokens.g.dart';

/// Sand & Sage: the visual style shared with the docs site and the web
/// dashboard (see AGENTS.md). Every color, radius and timing comes from
/// tokens.g.dart, generated from docs/src/data/tokens.json.
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
    accent: AiqBrandLight.accent,
    sage: AiqBrandLight.sage,
    ink: AiqBrandLight.ink,
    sand: AiqBrandLight.sand,
    wood: AiqBrandLight.wood,
    highlight: AiqBrandLight.highlight,
    ground: AiqBrandLight.ground,
    shadow: AiqBrandLight.shadow,
  );

  static const dark = AiqPalette(
    accent: AiqBrandDark.accent,
    sage: AiqBrandDark.sage,
    ink: AiqBrandDark.ink,
    sand: AiqBrandDark.sand,
    wood: AiqBrandDark.wood,
    highlight: AiqBrandDark.highlight,
    ground: AiqBrandDark.ground,
    shadow: AiqBrandDark.shadow,
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
const cardRadius = AiqRadii.card;

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? AiqPalette.dark : AiqPalette.light;
  final t = dark ? AiqSchemeTokens.dark : AiqSchemeTokens.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: brightness,
      ).copyWith(
        primary: t.primary,
        secondary: t.secondary,
        onPrimary: t.onPrimary,
        primaryContainer: t.primaryContainer,
        onPrimaryContainer: t.onPrimaryContainer,
        onSecondary: t.onSecondary,
        secondaryContainer: t.secondaryContainer,
        onSecondaryContainer: t.onSecondaryContainer,
        tertiary: t.tertiary,
        tertiaryContainer: t.tertiaryContainer,
        onTertiaryContainer: t.onTertiaryContainer,
        error: t.error,
        onError: t.onError,
        surface: t.surface,
        onSurface: t.onSurface,
        onSurfaceVariant: t.onSurfaceVariant,
        surfaceContainerLowest: t.surfaceContainerLowest,
        surfaceContainerLow: t.surfaceContainerLow,
        surfaceContainer: t.surfaceContainer,
        surfaceContainerHigh: t.surfaceContainerHigh,
        surfaceContainerHighest: t.surfaceContainerHighest,
        outline: t.outline,
        outlineVariant: t.outlineVariant,
        surfaceTint: Colors.transparent,
      );

  final roundedLg = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AiqRadii.lg),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AiqRadii.xl),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AiqRadii.lg),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AiqRadii.lg),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    listTileTheme: ListTileThemeData(shape: roundedLg),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: roundedLg,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AiqRadii.sheet),
      ),
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
