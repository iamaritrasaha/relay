import 'package:flutter/material.dart';

/// Typography hierarchy for Relay.
///
/// Geist Sans, kept deliberately light: the scale runs 400/500/600 and reserves
/// 700 for nothing at all, so hierarchy comes from size, colour and space
/// rather than from making every label loud. Falls back to the platform's own
/// sans, and always respects the user's text scaling.
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

  static TextStyle largeTitle(Color color, {bool isGnome = true}) => TextStyle(
    fontFamily: isGnome ? null : 'Geist',
    fontSize: 22,
    height: 1.25,
    fontWeight: semiBold,
    letterSpacing: -0.3,
    color: color,
    fontFamilyFallback: gnomeFontFallbacks,
  );

  static TextStyle title(Color color, {bool isGnome = true}) => TextStyle(
    fontFamily: isGnome ? null : 'Geist',
    fontSize: 17,
    height: 1.3,
    fontWeight: semiBold,
    letterSpacing: -0.2,
    color: color,
    fontFamilyFallback: gnomeFontFallbacks,
  );

  static TextStyle heading(Color color, {bool isGnome = true}) => TextStyle(
    fontFamily: isGnome ? null : 'Geist',
    fontSize: 15,
    height: 1.35,
    fontWeight: medium,
    color: color,
    fontFamilyFallback: gnomeFontFallbacks,
  );

  static TextStyle body(Color color, {bool isGnome = true, bool bold = false}) => TextStyle(
    fontFamily: isGnome ? null : 'Geist',
    fontSize: 14,
    height: 1.45,
    fontWeight: bold ? medium : regular,
    color: color,
    fontFamilyFallback: gnomeFontFallbacks,
  );

  static TextStyle subtitle(Color color, {bool isGnome = true}) => TextStyle(
    fontFamily: isGnome ? null : 'Geist',
    fontSize: 13,
    height: 1.4,
    fontWeight: regular,
    color: color,
    fontFamilyFallback: gnomeFontFallbacks,
  );

  static TextStyle caption(Color color, {bool isGnome = true}) => TextStyle(
    fontFamily: isGnome ? null : 'Geist',
    fontSize: 12.5,
    height: 1.35,
    fontWeight: regular,
    color: color,
    fontFamilyFallback: gnomeFontFallbacks,
  );

  static TextStyle sectionHeader(Color color, {bool isGnome = true}) => TextStyle(
    fontFamily: isGnome ? null : 'Geist',
    fontSize: 11,
    height: 1.3,
    fontWeight: medium,
    letterSpacing: 1.1,
    color: color,
    fontFamilyFallback: gnomeFontFallbacks,
  );

  static TextStyle monospace(Color color) => TextStyle(
    fontSize: 12,
    height: 1.4,
    fontFamily: 'monospace',
    fontFamilyFallback: monoFontFallbacks,
    color: color,
  );

  static TextStyle wordmark(Color color, {bool isGnome = true}) => TextStyle(
    fontFamily: isGnome ? null : 'Geist',
    fontSize: 16,
    height: 1.2,
    fontWeight: semiBold,
    letterSpacing: -0.2,
    color: color,
    fontFamilyFallback: gnomeFontFallbacks,
  );

  /// The focused device's name. The single loudest string on the page.
  static TextStyle deviceName(Color color, {bool isGnome = true}) => TextStyle(
    fontFamily: isGnome ? null : 'Geist',
    fontSize: 28,
    height: 1.15,
    fontWeight: semiBold,
    letterSpacing: -0.5,
    color: color,
    fontFamilyFallback: gnomeFontFallbacks,
  );

  /// A live number that carries meaning on its own: battery, signal, progress.
  static TextStyle metric(Color color, {bool isGnome = true}) => TextStyle(
    fontFamily: isGnome ? null : 'Geist',
    fontSize: 18,
    height: 1.2,
    fontWeight: semiBold,
    letterSpacing: -0.2,
    color: color,
    fontFamilyFallback: gnomeFontFallbacks,
  );

  /// Sidebar navigation entries.
  static TextStyle navLabel(Color color, {bool selected = false, bool isGnome = true}) => TextStyle(
    fontFamily: isGnome ? null : 'Geist',
    fontSize: 14,
    height: 1.2,
    fontWeight: medium,
    letterSpacing: -0.1,
    color: color,
    fontFamilyFallback: gnomeFontFallbacks,
  );

  static TextStyle pageTitle(Color color) => largeTitle(color);
  static TextStyle section(Color color) => sectionHeader(color);
  static TextStyle row(Color color) => body(color);
  static TextStyle value(Color color) => subtitle(color);
  static TextStyle legal(Color color) => caption(color);
}
