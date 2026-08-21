import 'package:flutter/material.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';

/// A deterministic, harmonized multicolor palette unique to a single device.
///
/// Each paired or connected device is assigned a stable 4-color palette
/// computed deterministically from its unique device ID. The palette is identical
/// across app restarts, reconnects, and page changes, without requiring database
/// storage.
@immutable
class RelayDevicePalette {
  /// The primary vibrant accent color for this device.
  final Color primary;

  /// The secondary harmonized color.
  final Color secondary;

  /// The tertiary harmonized color.
  final Color tertiary;

  /// The quaternary harmonized color.
  final Color quaternary;

  /// The brightness mode this palette has been adapted for.
  final Brightness brightness;

  /// A deterministic phase offset [0.0, 1.0) so multiple devices breathe
  /// and animate out of lockstep naturally.
  final double phaseOffset;

  /// The deterministic integer seed derived from the device ID.
  final int seed;

  const RelayDevicePalette({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.quaternary,
    required this.brightness,
    required this.phaseOffset,
    required this.seed,
  });

  bool get isDark => brightness == Brightness.dark;

  /// 5-stop loop for continuous perimeter sweeps.
  List<Color> get perimeterColors => [primary, secondary, tertiary, quaternary, primary];

  /// 4-stop colors for gradients and meshes.
  List<Color> get gradientColors => [primary, secondary, tertiary, quaternary];

  /// The four colors looped back to the primary for 360-degree sweep shaders.
  List<Color> get loopingGradientColors => [primary, secondary, tertiary, quaternary, primary];

  /// The main accent color.
  Color get accent => primary;

  /// Ambient wash color for surfaces.
  Color get washColor => primary.withValues(alpha: isDark ? 0.055 : 0.035);

  /// Ambient outer halo color.
  Color get haloColor => primary.withValues(alpha: isDark ? 0.09 : 0.05);

  /// Border highlight color.
  Color get borderAccent => primary.withValues(alpha: isDark ? 0.45 : 0.35);

  /// Deterministic palette families designed for high harmony and contrast.
  static const List<List<Color>> _darkFamilies = [
    // 0: Coral Flame (Relay signature warm spectrum)
    [Color(0xFFFF6F59), Color(0xFFFFB830), Color(0xFFF35588), Color(0xFF936BFF)],
    // 1: Ocean Teal (Crisp cyan-teal-indigo)
    [Color(0xFF00D2D3), Color(0xFF01A3A4), Color(0xFF2E86DE), Color(0xFF5F27CD)],
    // 2: Aurora Emerald (Mint, emerald, sky, cobalt)
    [Color(0xFF10AC84), Color(0xFF1DD1A1), Color(0xFF48DBFB), Color(0xFF2E86DE)],
    // 3: Sunset Rose (Tangerine, rose, crimson, violet)
    [Color(0xFFFF9F43), Color(0xFFFF6B6B), Color(0xFFEE5253), Color(0xFF833471)],
    // 4: Electric Orchid (Purple, indigo, aqua, ice)
    [Color(0xFFA55EEA), Color(0xFF4B7BEC), Color(0xFF26DE81), Color(0xFF2BCBBA)],
    // 5: Solar Amber (Gold, bright orange, crimson, rose)
    [Color(0xFFF7B731), Color(0xFFFA8231), Color(0xFFEB3B5A), Color(0xFFFD7272)],
    // 6: Neon Horizon (Pink, electric purple, cyan, azure)
    [Color(0xFFFD79A8), Color(0xFF6C5CE7), Color(0xFF00CEC9), Color(0xFF0984E3)],
    // 7: Lagoon Prism (Mint, teal, vivid blue, iris)
    [Color(0xFF55EFC4), Color(0xFF00B894), Color(0xFF0984E3), Color(0xFF6C5CE7)],
  ];

  static const List<List<Color>> _lightFamilies = [
    // 0: Coral Flame (Light: slightly deeper saturation for contrast)
    [Color(0xFFE24C38), Color(0xFFD97706), Color(0xFFD81B60), Color(0xFF7C3AED)],
    // 1: Ocean Teal
    [Color(0xFF0097A7), Color(0xFF00838F), Color(0xFF1976D2), Color(0xFF512DA8)],
    // 2: Aurora Emerald
    [Color(0xFF00897B), Color(0xFF00796B), Color(0xFF0288D1), Color(0xFF1565C0)],
    // 3: Sunset Rose
    [Color(0xFFE65100), Color(0xFFD81B60), Color(0xFFC2185B), Color(0xFF6A1B9A)],
    // 4: Electric Orchid
    [Color(0xFF8E24AA), Color(0xFF3949AB), Color(0xFF00897B), Color(0xFF0097A7)],
    // 5: Solar Amber
    [Color(0xFFD97706), Color(0xFFEA580C), Color(0xFFC026D3), Color(0xFFE11D48)],
    // 6: Neon Horizon
    [Color(0xFFD81B60), Color(0xFF5E35B1), Color(0xFF00838F), Color(0xFF0277BD)],
    // 7: Lagoon Prism
    [Color(0xFF00897B), Color(0xFF00695C), Color(0xFF0277BD), Color(0xFF5E35B1)],
  ];

  /// Deterministically derives a [RelayDevicePalette] from a device ID.
  factory RelayDevicePalette.fromDeviceId(
    String? rawDeviceId, {
    Brightness brightness = Brightness.dark,
  }) {
    if (rawDeviceId == null || rawDeviceId.isEmpty) {
      return RelayDevicePalette.fallback(brightness: brightness);
    }

    // Strip common protocol prefixes to normalize ID
    final id = rawDeviceId.replaceFirst('kdeconnect:', '').replaceFirst('relay:', '').trim();

    if (id.isEmpty) {
      return RelayDevicePalette.fallback(brightness: brightness);
    }

    final seed = _hashString(id);
    final families = brightness == Brightness.dark ? _darkFamilies : _lightFamilies;
    final familyIndex = (seed.abs()) % families.length;
    final baseColors = families[familyIndex];

    // Secondary hash bits determine permutation/rotation to prevent collisions
    final rotation = (seed >> 8).abs() % baseColors.length;
    final rotated = <Color>[
      for (int i = 0; i < baseColors.length; i++) baseColors[(i + rotation) % baseColors.length],
    ];

    // Phase offset [0.0, 1.0) derived deterministically from the lower 16 bits
    final phaseOffset = ((seed & 0xFFFF) / 65536.0);

    return RelayDevicePalette(
      primary: rotated[0],
      secondary: rotated[1],
      tertiary: rotated[2],
      quaternary: rotated[3],
      brightness: brightness,
      phaseOffset: phaseOffset,
      seed: seed,
    );
  }

  /// Derives a [RelayDevicePalette] from a [RelayDeviceVm].
  factory RelayDevicePalette.fromDevice(
    RelayDeviceVm? device, {
    Brightness brightness = Brightness.dark,
  }) {
    if (device == null) {
      return RelayDevicePalette.fallback(brightness: brightness);
    }
    // Prefer device.relayId or device.lanFingerprint or device.key (never name alone)
    final id = device.relayId ?? (device.lanFingerprint?.isNotEmpty == true ? device.lanFingerprint! : device.key);
    return RelayDevicePalette.fromDeviceId(id, brightness: brightness);
  }

  /// Default fallback palette matching Relay's brand accent family.
  factory RelayDevicePalette.fallback({Brightness brightness = Brightness.dark}) {
    final isDark = brightness == Brightness.dark;
    return RelayDevicePalette(
      primary: isDark ? const Color(0xFFFF6F59) : const Color(0xFFE24C38),
      secondary: isDark ? const Color(0xFFFFB830) : const Color(0xFFD97706),
      tertiary: isDark ? const Color(0xFFF35588) : const Color(0xFFD81B60),
      quaternary: isDark ? const Color(0xFF936BFF) : const Color(0xFF7C3AED),
      brightness: brightness,
      phaseOffset: 0.0,
      seed: 0,
    );
  }

  /// 32-bit FNV-1a hash for high distribution uniformity.
  static int _hashString(String input) {
    var hash = 0x811c9dc5;
    for (int i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Linearly interpolate between two palettes.
  static RelayDevicePalette lerp(RelayDevicePalette a, RelayDevicePalette b, double t) {
    return RelayDevicePalette(
      primary: Color.lerp(a.primary, b.primary, t)!,
      secondary: Color.lerp(a.secondary, b.secondary, t)!,
      tertiary: Color.lerp(a.tertiary, b.tertiary, t)!,
      quaternary: Color.lerp(a.quaternary, b.quaternary, t)!,
      brightness: t < 0.5 ? a.brightness : b.brightness,
      phaseOffset: (a.phaseOffset + (b.phaseOffset - a.phaseOffset) * t) % 1.0,
      seed: t < 0.5 ? a.seed : b.seed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelayDevicePalette &&
          runtimeType == other.runtimeType &&
          primary == other.primary &&
          secondary == other.secondary &&
          tertiary == other.tertiary &&
          quaternary == other.quaternary &&
          brightness == other.brightness &&
          phaseOffset == other.phaseOffset &&
          seed == other.seed;

  @override
  int get hashCode => Object.hash(primary, secondary, tertiary, quaternary, brightness, phaseOffset, seed);
}
