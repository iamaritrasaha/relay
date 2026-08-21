import 'package:flutter/material.dart';

export 'package:relay_app/config/relay_device_palette.dart';
export 'package:relay_app/config/relay_typography.dart';

abstract final class RelayProduct {
  static const name = 'Relay';
  static const tagline = 'One desktop for all the devices around you.';
  static const copyright = '© 2026 Aritra Saha';
  static const localSendAttribution = 'Portions based on LocalSend, licensed under the Apache License 2.0.';
}

/// Relay's product-facing palette. Keep product colors here rather than in
/// individual screens so platform and Flutter surfaces share the same roles.
@immutable
class RelayPalette {
  final Color canvas;
  final Color canvasTonalHigh;
  final Color canvasTonalLow;
  final Color elevated;
  final Color softSurface;
  final Color hoverSurface;
  final Color hairline;
  final Color topHighlight;
  final Color accent;
  final Color accentSoft;
  final Color accentSecondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color success;
  final Color warning;
  final Color error;

  const RelayPalette({
    required this.canvas,
    required this.canvasTonalHigh,
    required this.canvasTonalLow,
    required this.elevated,
    required this.softSurface,
    required this.hoverSurface,
    required this.hairline,
    required this.topHighlight,
    required this.accent,
    required this.accentSoft,
    required this.accentSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.success,
    required this.warning,
    required this.error,
  });

  /// Relay Carbon — warm neutral carbon. No purple cast, no blue cast: the
  /// greys carry a faint amber so the accent sits inside the same family
  /// rather than on top of a cool ground.
  static const dark = RelayPalette(
    canvas: Color(0xff242424),
    canvasTonalHigh: Color(0xff2c2c2c),
    canvasTonalLow: Color(0xff1e1e1e),
    elevated: Color(0xff303030),
    softSurface: Color(0xff383838),
    hoverSurface: Color(0xff424242),
    hairline: Color(0x1fffffff),
    topHighlight: Color(0x00000000),
    accent: Color(0xffe95420),
    accentSoft: Color(0xffff7846),
    accentSecondary: Color(0xffc89a55),
    textPrimary: Color(0xfff6f6f6),
    textSecondary: Color(0xffb0b0b0),
    textTertiary: Color(0xff787878),
    success: Color(0xff2ec27e),
    warning: Color(0xffe5a50a),
    error: Color(0xffe01b24),
  );

  /// Relay Yaru / GNOME palette, light.
  static const light = RelayPalette(
    canvas: Color(0xfff6f6f6),
    canvasTonalHigh: Color(0xffffffff),
    canvasTonalLow: Color(0xffeeeeee),
    elevated: Color(0xffffffff),
    softSurface: Color(0xffececec),
    hoverSurface: Color(0xffe2e2e2),
    hairline: Color(0x14000000),
    topHighlight: Color(0x00000000),
    accent: Color(0xffe95420),
    accentSoft: Color(0xffc44012),
    accentSecondary: Color(0xff8a6420),
    textPrimary: Color(0xff1e1e1e),
    textSecondary: Color(0xff5c5c5c),
    textTertiary: Color(0xff8c8c8c),
    success: Color(0xff26a269),
    warning: Color(0xffc67800),
    error: Color(0xffc01c28),
  );

  static const brandAccent = Color(0xfff07855);
  static const brandAccentDark = Color(0xffc0522f);

  static RelayPalette of(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}

/// Small, shared layout and type constants for Relay's product UI.
abstract final class RelayComponentTokens {
  static const double groupedRadius = RelayRadius.panel;
  static const double dialogRadius = RelayRadius.card;
  static const double compactControlHeight = 40;
  static const double sectionTracking = 1.1;
}

/// GNOME/Yaru corner hierarchy.
///
/// These values intentionally describe the outer geometry of a surface, not
/// its visual prominence. Keep group children square and clip them at their
/// shared parent rather than turning every row into an individual card.
abstract final class RelayRadius {
  /// Major surfaces and dialogs.
  static const double hero = 14;

  /// Cards and message bubbles.
  static const double card = 12;

  /// Boxed preference/list groups and inputs.
  static const double panel = 12;

  /// Interactive rows and compact surfaces.
  static const double action = 10;

  /// Sidebar rows and navigation items.
  static const double nav = 8;

  /// Normal buttons.
  static const double button = 8;

  /// Small chips that really are pills.
  static const double pill = 999;
}

/// Depth for Relay Carbon: contrast plus one restrained shadow, never blur.
abstract final class RelayElevation {
  static List<BoxShadow> resting(Brightness brightness) => const [];

  static List<BoxShadow> lifted(Brightness brightness) => brightness == Brightness.dark
      ? const [BoxShadow(color: Color(0x33000000), blurRadius: 22, spreadRadius: -10, offset: Offset(0, 6))]
      : const [BoxShadow(color: Color(0x121a1815), blurRadius: 18, spreadRadius: -8, offset: Offset(0, 4))];
}

ColorScheme relayColorScheme(Brightness brightness) {
  final palette = RelayPalette.of(brightness);
  final isDark = brightness == Brightness.dark;

  return ColorScheme(
    brightness: brightness,
    primary: palette.accent,
    onPrimary: isDark ? const Color(0xff2b100a) : const Color(0xffffffff),
    primaryContainer: isDark ? const Color(0xff45231b) : const Color(0xfff7ddd4),
    onPrimaryContainer: isDark ? const Color(0xffffd9cd) : const Color(0xff4a1a0d),
    secondary: palette.accentSecondary,
    onSecondary: isDark ? const Color(0xff1b131e) : const Color(0xffffffff),
    secondaryContainer: isDark ? const Color(0xff342b39) : const Color(0xffe9dfec),
    onSecondaryContainer: isDark ? const Color(0xffecdcf1) : const Color(0xff2d2032),
    tertiary: palette.success,
    onTertiary: isDark ? const Color(0xff0d2118) : const Color(0xffffffff),
    tertiaryContainer: isDark ? const Color(0xff1c3d2d) : const Color(0xffc9eeda),
    onTertiaryContainer: isDark ? const Color(0xffbdf2d3) : const Color(0xff00391f),
    error: palette.error,
    onError: isDark ? const Color(0xff2b100f) : const Color(0xffffffff),
    errorContainer: isDark ? const Color(0xff522421) : const Color(0xffffdad5),
    onErrorContainer: isDark ? const Color(0xffffdad5) : const Color(0xff410002),
    surface: palette.canvas,
    onSurface: palette.textPrimary,
    surfaceContainerHighest: palette.elevated,
    onSurfaceVariant: palette.textSecondary,
    outline: palette.textTertiary,
    outlineVariant: isDark ? const Color(0xff322d35) : const Color(0xffdcd5da),
    shadow: const Color(0xff000000),
    scrim: const Color(0xff000000),
    inverseSurface: isDark ? const Color(0xfff4f1f4) : const Color(0xff2e2a30),
    onInverseSurface: isDark ? const Color(0xff1c191f) : const Color(0xfff7f4f6),
    inversePrimary: isDark ? const Color(0xffc24d30) : const Color(0xffff9c85),
    surfaceTint: palette.accent,
  );
}

extension RelayThemeData on ThemeData {
  RelayPalette get relayPalette => RelayPalette.of(brightness);
}
