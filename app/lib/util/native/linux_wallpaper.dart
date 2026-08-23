import 'dart:async';
import 'dart:io';

/// Resolves the current local Linux desktop wallpaper asynchronously.
///
/// Fully decoupled from startup, networking, Rust, FRB, and device state.
/// If any error, timeout, or unsupported desktop environment occurs, it returns `null`.
class LinuxWallpaperService {
  const LinuxWallpaperService._();

  static const List<String> _supportedExtensions = [
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.bmp',
    '.svg',
  ];

  /// Discovers the local desktop wallpaper path asynchronously.
  static Future<String?> discoverLocalWallpaper({
    Duration timeout = const Duration(milliseconds: 1500),
    Map<String, String>? environmentOverride,
  }) async {
    if (!Platform.isLinux && environmentOverride == null) {
      return null;
    }

    try {
      return await _resolveWallpaper(environmentOverride).timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _resolveWallpaper(Map<String, String>? env) async {
    final environment = env ?? Platform.environment;
    final desktop = (environment['XDG_CURRENT_DESKTOP'] ?? environment['DESKTOP_SESSION'] ?? '').toLowerCase();

    // 1. Try DE-specific discovery first
    if (desktop.contains('gnome') || desktop.contains('unity') || desktop.contains('pantheon') || desktop.contains('ubuntu')) {
      final gnome = await _discoverGnome();
      if (gnome != null) return gnome;
    } else if (desktop.contains('cinnamon')) {
      final cinnamon = await _discoverCinnamon();
      if (cinnamon != null) return cinnamon;
    } else if (desktop.contains('kde') || desktop.contains('plasma')) {
      final kde = await _discoverKde(environment);
      if (kde != null) return kde;
    } else if (desktop.contains('xfce')) {
      final xfce = await _discoverXfce();
      if (xfce != null) return xfce;
    }

    // 2. Generic fallbacks across standard tools
    final fallbackGnome = await _discoverGnome();
    if (fallbackGnome != null) return fallbackGnome;

    final fallbackKde = await _discoverKde(environment);
    if (fallbackKde != null) return fallbackKde;

    final fallbackCinnamon = await _discoverCinnamon();
    if (fallbackCinnamon != null) return fallbackCinnamon;

    final fallbackXfce = await _discoverXfce();
    if (fallbackXfce != null) return fallbackXfce;

    return null;
  }

  /// GNOME / Unity: `gsettings get org.gnome.desktop.background picture-uri(-dark)`
  static Future<String?> _discoverGnome() async {
    try {
      // Check dark background first
      final darkResult = await Process.run('gsettings', ['get', 'org.gnome.desktop.background', 'picture-uri-dark']);
      if (darkResult.exitCode == 0) {
        final path = parseWallpaperOutput(darkResult.stdout.toString());
        if (path != null) return path;
      }

      // Check standard background
      final result = await Process.run('gsettings', ['get', 'org.gnome.desktop.background', 'picture-uri']);
      if (result.exitCode == 0) {
        final path = parseWallpaperOutput(result.stdout.toString());
        if (path != null) return path;
      }
    } catch (_) {}
    return null;
  }

  /// Cinnamon: `gsettings get org.cinnamon.desktop.background picture-uri`
  static Future<String?> _discoverCinnamon() async {
    try {
      final result = await Process.run('gsettings', ['get', 'org.cinnamon.desktop.background', 'picture-uri']);
      if (result.exitCode == 0) {
        final path = parseWallpaperOutput(result.stdout.toString());
        if (path != null) return path;
      }
    } catch (_) {}
    return null;
  }

  /// KDE Plasma: config file parsing or kreadconfig
  static Future<String?> _discoverKde(Map<String, String> env) async {
    try {
      final home = env['HOME'] ?? Platform.environment['HOME'];
      if (home != null) {
        final configFile = File('$home/.config/plasma-org.kde.plasma.desktop-appletsrc');
        if (configFile.existsSync()) {
          final content = await configFile.readAsString();
          final path = _extractKdeWallpaperPath(content);
          if (path != null && _isValidWallpaperFile(path)) {
            return path;
          }
        }
      }

      // Fallback: kreadconfig6 / kreadconfig5
      for (final tool in ['kreadconfig6', 'kreadconfig5']) {
        try {
          final result = await Process.run(tool, [
            '--file',
            'plasma-org.kde.plasma.desktop-appletsrc',
            '--group',
            'Containments',
            '--key',
            'Image',
          ]);
          if (result.exitCode == 0) {
            final path = parseWallpaperOutput(result.stdout.toString());
            if (path != null) return path;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  /// XFCE: `xfconf-query -c xfce4-desktop -p ...`
  static Future<String?> _discoverXfce() async {
    try {
      final listResult = await Process.run('xfconf-query', ['-c', 'xfce4-desktop', '-l']);
      if (listResult.exitCode == 0) {
        final lines = listResult.stdout.toString().split('\n');
        for (final line in lines) {
          final prop = line.trim();
          if (prop.contains('/last-image') || prop.contains('/image-path')) {
            final valResult = await Process.run('xfconf-query', ['-c', 'xfce4-desktop', '-p', prop]);
            if (valResult.exitCode == 0) {
              final path = parseWallpaperOutput(valResult.stdout.toString());
              if (path != null) return path;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Extracts wallpaper path from KDE desktop-appletsrc content.
  static String? _extractKdeWallpaperPath(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('Image=')) {
        final raw = trimmed.substring('Image='.length).trim();
        final parsed = parseWallpaperOutput(raw);
        if (parsed != null) return parsed;
      }
      if (trimmed.startsWith('usersWallpapers=')) {
        final raw = trimmed.substring('usersWallpapers='.length).trim();
        final first = raw.split(',').firstOrNull?.trim();
        if (first != null) {
          final parsed = parseWallpaperOutput(first);
          if (parsed != null) return parsed;
        }
      }
    }
    return null;
  }

  /// Parses raw command output or config string into an absolute file path.
  static String? parseWallpaperOutput(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // Strip outer quotes if present (e.g. 'file:///...' or "file:///...")
    if ((trimmed.startsWith("'") && trimmed.endsWith("'")) || (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
      if (trimmed.length >= 2) {
        trimmed = trimmed.substring(1, trimmed.length - 1).trim();
      }
    }

    if (trimmed.isEmpty) return null;

    String candidatePath;
    if (trimmed.startsWith('file://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) return null;
      candidatePath = uri.toFilePath();
    } else {
      candidatePath = trimmed;
    }

    if (_isValidWallpaperFile(candidatePath)) {
      return candidatePath;
    }
    return null;
  }

  static bool _isValidWallpaperFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) return false;

      final lower = path.toLowerCase();
      return _supportedExtensions.any((ext) => lower.endsWith(ext));
    } catch (_) {
      return false;
    }
  }
}
