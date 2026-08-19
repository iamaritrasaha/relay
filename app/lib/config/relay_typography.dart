import 'package:flutter/material.dart';

/// Typography hierarchy for Relay.
///
/// Follows GNOME / Adwaita guidelines on Linux / Desktop (Large Title, Title, Heading,
/// Body, Caption, Monospace) and Material 3 guidelines on Android, respecting user
/// system text scaling without forcing external novelty fonts.
abstract final class RelayTypography {
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  /// System sans font families for GNOME / Linux
  static const List<String> gnomeFontFallbacks = [
    'Adwaita Sans',
    'Cantarell',
    'Ubuntu',
    'DejaVu Sans',
    'Liberation Sans',
    'sans-serif',
  ];

  /// Monospace font families for technical diagnostics and IDs
  static const List<String> monoFontFallbacks = [
    'Adwaita Mono',
    'Source Code Pro',
    'Ubuntu Mono',
    'DejaVu Sans Mono',
    'monospace',
  ];

  static TextStyle largeTitle(Color color, {bool isGnome = false}) => TextStyle(
    fontSize: isGnome ? 24 : 26,
    height: 1.25,
    fontWeight: bold,
    letterSpacing: isGnome ? -0.2 : 0,
    color: color,
    fontFamilyFallback: isGnome ? gnomeFontFallbacks : null,
  );

  static TextStyle title(Color color, {bool isGnome = false}) => TextStyle(
    fontSize: isGnome ? 18 : 20,
    height: 1.3,
    fontWeight: semiBold,
    letterSpacing: isGnome ? -0.1 : 0,
    color: color,
    fontFamilyFallback: isGnome ? gnomeFontFallbacks : null,
  );

  static TextStyle heading(Color color, {bool isGnome = false}) => TextStyle(
    fontSize: isGnome ? 15 : 16,
    height: 1.35,
    fontWeight: semiBold,
    color: color,
    fontFamilyFallback: isGnome ? gnomeFontFallbacks : null,
  );

  static TextStyle body(Color color, {bool isGnome = false, bool bold = false}) => TextStyle(
    fontSize: isGnome ? 13.5 : 14,
    height: 1.4,
    fontWeight: bold ? semiBold : regular,
    color: color,
    fontFamilyFallback: isGnome ? gnomeFontFallbacks : null,
  );

  static TextStyle subtitle(Color color, {bool isGnome = false}) => TextStyle(
    fontSize: isGnome ? 12 : 13,
    height: 1.35,
    fontWeight: regular,
    color: color,
    fontFamilyFallback: isGnome ? gnomeFontFallbacks : null,
  );

  static TextStyle caption(Color color, {bool isGnome = false}) => TextStyle(
    fontSize: isGnome ? 11 : 12,
    height: 1.3,
    fontWeight: regular,
    color: color,
    fontFamilyFallback: isGnome ? gnomeFontFallbacks : null,
  );

  static TextStyle sectionHeader(Color color, {bool isGnome = false}) => TextStyle(
    fontSize: isGnome ? 11.5 : 12,
    height: 1.3,
    fontWeight: semiBold,
    letterSpacing: isGnome ? 0.8 : 0.5,
    color: color,
    fontFamilyFallback: isGnome ? gnomeFontFallbacks : null,
  );

  static TextStyle monospace(Color color) => TextStyle(
    fontSize: 12,
    height: 1.4,
    fontFamily: 'monospace',
    fontFamilyFallback: monoFontFallbacks,
    color: color,
  );

  static TextStyle wordmark(Color color) => TextStyle(
    fontSize: 17,
    height: 1.2,
    fontWeight: semiBold,
    letterSpacing: -0.2,
    color: color,
  );

  static TextStyle pageTitle(Color color) => largeTitle(color);
  static TextStyle section(Color color) => sectionHeader(color);
  static TextStyle row(Color color) => body(color);
  static TextStyle value(Color color) => subtitle(color);
  static TextStyle legal(Color color) => caption(color);
}
