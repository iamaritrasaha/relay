// dart format width=150

/// GENERATED CODE - DO NOT MODIFY BY HAND
/// *****************************************************
///  FlutterGen
/// *****************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: deprecated_member_use,directives_ordering,implicit_dynamic_list_literal,unnecessary_import

import 'package:flutter/widgets.dart';

class $AssetsImgGen {
  const $AssetsImgGen();

  /// File path: assets/img/logo-128.png
  AssetGenImage get logo128 => const AssetGenImage('assets/img/logo-128.png');

  /// File path: assets/img/logo-256.png
  AssetGenImage get logo256 => const AssetGenImage('assets/img/logo-256.png');

  /// File path: assets/img/logo-32-black.png
  AssetGenImage get logo32Black => const AssetGenImage('assets/img/logo-32-black.png');

  /// File path: assets/img/logo-32-white.png
  AssetGenImage get logo32White => const AssetGenImage('assets/img/logo-32-white.png');

  /// File path: assets/img/logo-32.png
  AssetGenImage get logo32 => const AssetGenImage('assets/img/logo-32.png');

  /// File path: assets/img/logo-512-white.png
  AssetGenImage get logo512White => const AssetGenImage('assets/img/logo-512-white.png');

  /// File path: assets/img/logo-512.png
  AssetGenImage get logo512 => const AssetGenImage('assets/img/logo-512.png');

  /// File path: assets/img/logo.ico
  String get logo => 'assets/img/logo.ico';

  /// File path: assets/img/relay-adaptive-background.svg
  String get relayAdaptiveBackground => 'assets/img/relay-adaptive-background.svg';

  /// File path: assets/img/relay-adaptive-foreground.svg
  String get relayAdaptiveForeground => 'assets/img/relay-adaptive-foreground.svg';

  /// File path: assets/img/relay-icon-linux-512.png
  AssetGenImage get relayIconLinux512 => const AssetGenImage('assets/img/relay-icon-linux-512.png');

  /// File path: assets/img/relay-icon-linux.svg
  String get relayIconLinux => 'assets/img/relay-icon-linux.svg';

  /// File path: assets/img/relay-icon-sheet.svg
  String get relayIconSheet => 'assets/img/relay-icon-sheet.svg';

  /// File path: assets/img/relay-icon.ico
  String get relayIconIco => 'assets/img/relay-icon.ico';

  /// File path: assets/img/relay-icon.png
  AssetGenImage get relayIconPng => const AssetGenImage('assets/img/relay-icon.png');

  /// File path: assets/img/relay-launcher-android-512.png
  AssetGenImage get relayLauncherAndroid512 => const AssetGenImage('assets/img/relay-launcher-android-512.png');

  /// File path: assets/img/relay-launcher-android.svg
  String get relayLauncherAndroid => 'assets/img/relay-launcher-android.svg';

  /// File path: assets/img/relay-symbol-compact.svg
  String get relaySymbolCompact => 'assets/img/relay-symbol-compact.svg';

  /// File path: assets/img/relay-symbol-mono.svg
  String get relaySymbolMono => 'assets/img/relay-symbol-mono.svg';

  /// File path: assets/img/relay-symbol-sheet.png
  AssetGenImage get relaySymbolSheet => const AssetGenImage('assets/img/relay-symbol-sheet.png');

  /// File path: assets/img/relay-symbol.svg
  String get relaySymbol => 'assets/img/relay-symbol.svg';

  /// File path: assets/img/relay-tray-black.png
  AssetGenImage get relayTrayBlack => const AssetGenImage('assets/img/relay-tray-black.png');

  /// File path: assets/img/relay-tray-white.png
  AssetGenImage get relayTrayWhite => const AssetGenImage('assets/img/relay-tray-white.png');

  /// List of all assets
  List<dynamic> get values => [
    logo128,
    logo256,
    logo32Black,
    logo32White,
    logo32,
    logo512White,
    logo512,
    logo,
    relayAdaptiveBackground,
    relayAdaptiveForeground,
    relayIconLinux512,
    relayIconLinux,
    relayIconSheet,
    relayIconIco,
    relayIconPng,
    relayLauncherAndroid512,
    relayLauncherAndroid,
    relaySymbolCompact,
    relaySymbolMono,
    relaySymbolSheet,
    relaySymbol,
    relayTrayBlack,
    relayTrayWhite,
  ];
}

abstract final class Assets {
  static const String changelogRelay = 'CHANGELOG_RELAY.md';
  static const String changelog = 'assets/CHANGELOG.md';
  static const $AssetsImgGen img = $AssetsImgGen();

  /// List of all assets
  static List<String> get values => [changelogRelay, changelog];
}

class AssetGenImage {
  const AssetGenImage(this._assetName, {this.size, this.flavors = const {}, this.animation});

  final String _assetName;

  final Size? size;
  final Set<String> flavors;
  final AssetGenImageAnimation? animation;

  Image image({
    Key? key,
    AssetBundle? bundle,
    ImageFrameBuilder? frameBuilder,
    ImageErrorWidgetBuilder? errorBuilder,
    String? semanticLabel,
    bool excludeFromSemantics = false,
    double? scale,
    double? width,
    double? height,
    Color? color,
    Animation<double>? opacity,
    BlendMode? colorBlendMode,
    BoxFit? fit,
    AlignmentGeometry alignment = Alignment.center,
    ImageRepeat repeat = ImageRepeat.noRepeat,
    Rect? centerSlice,
    bool matchTextDirection = false,
    bool gaplessPlayback = true,
    bool isAntiAlias = false,
    String? package,
    FilterQuality filterQuality = FilterQuality.medium,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    return Image.asset(
      _assetName,
      key: key,
      bundle: bundle,
      frameBuilder: frameBuilder,
      errorBuilder: errorBuilder,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      scale: scale,
      width: width,
      height: height,
      color: color,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      gaplessPlayback: gaplessPlayback,
      isAntiAlias: isAntiAlias,
      package: package,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }

  ImageProvider provider({AssetBundle? bundle, String? package}) {
    return AssetImage(_assetName, bundle: bundle, package: package);
  }

  String get path => _assetName;

  String get keyName => _assetName;
}

class AssetGenImageAnimation {
  const AssetGenImageAnimation({required this.isAnimation, required this.duration, required this.frames});

  final bool isAnimation;
  final Duration duration;
  final int frames;
}
