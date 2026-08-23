import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/provider/local_wallpaper_provider.dart';
import 'package:relay_app/util/native/linux_wallpaper.dart';

void main() {
  group('LinuxWallpaperService', () {
    test('parseWallpaperOutput parses file URI correctly if file exists', () {
      // Check on an existing system image or test asset
      const validPath = '/usr/share/backgrounds/warty-final-ubuntu.png';
      if (File(validPath).existsSync()) {
        final parsed = LinuxWallpaperService.parseWallpaperOutput("'file://$validPath'");
        expect(parsed, equals(validPath));

        final doubleQuoted = LinuxWallpaperService.parseWallpaperOutput('"file://$validPath"');
        expect(doubleQuoted, equals(validPath));

        final plainPath = LinuxWallpaperService.parseWallpaperOutput("'$validPath'");
        expect(plainPath, equals(validPath));
      }
    });

    test('parseWallpaperOutput returns null for empty, invalid, or non-existent files', () {
      expect(LinuxWallpaperService.parseWallpaperOutput(''), isNull);
      expect(LinuxWallpaperService.parseWallpaperOutput("''"), isNull);
      expect(LinuxWallpaperService.parseWallpaperOutput("'file:///non/existent/file.png'"), isNull);
      expect(LinuxWallpaperService.parseWallpaperOutput('/non/existent/image.jpg'), isNull);
    });

    test('discoverLocalWallpaper returns null or valid image without throwing', () async {
      final wallpaper = await LinuxWallpaperService.discoverLocalWallpaper();
      if (wallpaper != null) {
        expect(File(wallpaper).existsSync(), isTrue);
      }
    });

    test('discoverLocalWallpaper safely returns null on unsupported DE', () async {
      final wallpaper = await LinuxWallpaperService.discoverLocalWallpaper(
        environmentOverride: {
          'XDG_CURRENT_DESKTOP': 'UNKNOWN_CUSTOM_DE',
          'DESKTOP_SESSION': 'unknown',
          'HOME': '/non/existent/home',
        },
      );
      // Even if fallback gsettings runs, it either finds valid wallpaper or returns null safely without throwing
      if (wallpaper != null) {
        expect(File(wallpaper).existsSync(), isTrue);
      }
    });
  });

  group('LocalWallpaperProvider', () {
    test('starts with null and fetches wallpaper asynchronously without throwing', () async {
      final ref = RefenaContainer();
      expect(ref.read(localWallpaperProvider), isNull);

      await ref.notifier(localWallpaperProvider).fetchWallpaper();
      final current = ref.read(localWallpaperProvider);
      if (current != null) {
        expect(File(current).existsSync(), isTrue);
        expect(ref.notifier(localWallpaperProvider).getImageProvider(), isNotNull);
      } else {
        expect(ref.notifier(localWallpaperProvider).getImageProvider(), isNull);
      }
    });
  });
}
