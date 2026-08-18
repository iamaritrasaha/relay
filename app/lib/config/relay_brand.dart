import 'package:flutter/material.dart';

export 'package:localsend_app/config/relay_typography.dart';

abstract final class RelayProduct {
  static const name = 'Relay';
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

  static const dark = RelayPalette(
    canvas: Color(0xff121318),
    canvasTonalHigh: Color(0xff15161b),
    canvasTonalLow: Color(0xff0e0f13),
    elevated: Color(0xff191b22),
    softSurface: Color(0x0ffffffF),
    hairline: Color(0x0effffff),
    topHighlight: Color(0x14ffffff),
    accent: Color(0xff7d8fff),
    accentSoft: Color(0xffaab5ff),
    accentSecondary: Color(0xff6ea8ff),
    textPrimary: Color(0xfff5f6fa),
    textSecondary: Color(0xff8e94a4),
    textTertiary: Color(0xff6e7482),
    success: Color(0xff69d49a),
    warning: Color(0xffe0a65c),
    error: Color(0xffe8796f),
  );

  static const light = RelayPalette(
    canvas: Color(0xfff8f8fc),
    canvasTonalHigh: Color(0xfffdfdff),
    canvasTonalLow: Color(0xffeef0f6),
    elevated: Color(0xffffffff),
    softSurface: Color(0x0f171920),
    hairline: Color(0x14171920),
    topHighlight: Color(0xaaffffff),
    accent: Color(0xff5368d6),
    accentSoft: Color(0xff4055bd),
    accentSecondary: Color(0xff3d7ed5),
    textPrimary: Color(0xff171920),
    textSecondary: Color(0xff565d6d),
    textTertiary: Color(0xff747b8a),
    success: Color(0xff247a4a),
    warning: Color(0xff9d671f),
    error: Color(0xffb94741),
  );

  static RelayPalette of(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}

/// Small, shared layout and type constants for Relay's product UI.
abstract final class RelayComponentTokens {
  static const double groupedRadius = 15;
  static const double dialogRadius = 24;
  static const double compactControlHeight = 40;
  static const double sectionTracking = 1.1;
}

ColorScheme relayColorScheme(Brightness brightness) {
  final palette = RelayPalette.of(brightness);
  if (brightness == Brightness.dark) {
    return const ColorScheme.dark(
      primary: Color(0xff7d8fff),
      onPrimary: Color(0xfff5f6fa),
      primaryContainer: Color(0xff303867),
      onPrimaryContainer: Color(0xffdce0ff),
      secondary: Color(0xff6ea8ff),
      onSecondary: Color(0xff10131a),
      secondaryContainer: Color(0xff202c47),
      onSecondaryContainer: Color(0xffdce7ff),
      tertiary: Color(0xff69d49a),
      onTertiary: Color(0xff102119),
      tertiaryContainer: Color(0xff1c4030),
      onTertiaryContainer: Color(0xffb7f4cf),
      error: Color(0xffe8796f),
      onError: Color(0xff2b100f),
      errorContainer: Color(0xff542522),
      onErrorContainer: Color(0xffffdad5),
      surface: Color(0xff121318),
      onSurface: Color(0xfff5f6fa),
      surfaceContainerHighest: Color(0xff191b22),
      onSurfaceVariant: Color(0xff8e94a4),
      outline: Color(0xff6e7482),
      outlineVariant: Color(0xff2c2f38),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xfff5f6fa),
      onInverseSurface: Color(0xff1a1b20),
      inversePrimary: Color(0xff5368d6),
      surfaceTint: Color(0xff7d8fff),
    );
  }

  return ColorScheme.light(
    primary: palette.accent,
    onPrimary: const Color(0xffffffff),
    primaryContainer: const Color(0xffe0e5ff),
    onPrimaryContainer: const Color(0xff17235f),
    secondary: palette.accentSecondary,
    onSecondary: const Color(0xffffffff),
    secondaryContainer: const Color(0xffdce9ff),
    onSecondaryContainer: const Color(0xff0c315c),
    tertiary: palette.success,
    onTertiary: const Color(0xffffffff),
    tertiaryContainer: const Color(0xffc9f2d8),
    onTertiaryContainer: const Color(0xff00391d),
    error: palette.error,
    onError: const Color(0xffffffff),
    errorContainer: const Color(0xffffdad5),
    onErrorContainer: const Color(0xff410002),
    surface: palette.canvas,
    onSurface: palette.textPrimary,
    surfaceContainerHighest: palette.elevated,
    onSurfaceVariant: palette.textSecondary,
    outline: palette.textTertiary,
    outlineVariant: const Color(0xffd7d9e2),
    shadow: const Color(0xff000000),
    scrim: const Color(0xff000000),
    inverseSurface: const Color(0xff2d3038),
    onInverseSurface: const Color(0xfff4f5f9),
    inversePrimary: const Color(0xffaab5ff),
    surfaceTint: palette.accent,
  );
}

extension RelayThemeData on ThemeData {
  RelayPalette get relayPalette => RelayPalette.of(brightness);
}
