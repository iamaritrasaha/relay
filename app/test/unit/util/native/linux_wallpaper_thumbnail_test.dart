import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:relay_app/util/native/linux_wallpaper_thumbnail.dart';

void main() {
  group('LinuxWallpaperThumbnailService', () {
    late Directory tempDir;
    late File testImageFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('relay_wallpaper_test_');
      testImageFile = File('${tempDir.path}/test_source.png');

      // Create a test 1920x1080 image
      final testImage = img.Image(width: 1920, height: 1080);
      img.fill(testImage, color: img.ColorRgb8(100, 150, 200));
      final pngBytes = img.encodePng(testImage);
      await testImageFile.writeAsBytes(pngBytes);
    });

    tearDown(() async {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('getThumbnailForWallpaper generates a 1280x800 JPEG <= 1MB', () async {
      final result = await LinuxWallpaperThumbnailService.getThumbnailForWallpaper(testImageFile.path);
      expect(result, isNotNull);
      expect(result!.width, equals(1280));
      expect(result.height, equals(800));
      expect(result.hash, isNotEmpty);

      final thumbFile = File(result.path);
      expect(thumbFile.existsSync(), isTrue);

      final thumbBytes = await thumbFile.readAsBytes();
      expect(thumbBytes.length, lessThanOrEqualTo(1048576));

      final decodedThumb = img.decodeImage(thumbBytes);
      expect(decodedThumb, isNotNull);
      expect(decodedThumb!.width, equals(1280));
      expect(decodedThumb.height, equals(800));
    });

    test('content hash is stable across identical input', () async {
      final result1 = await LinuxWallpaperThumbnailService.getThumbnailForWallpaper(testImageFile.path);
      final result2 = await LinuxWallpaperThumbnailService.getThumbnailForWallpaper(testImageFile.path);
      expect(result1, isNotNull);
      expect(result2, isNotNull);
      expect(result1!.hash, equals(result2!.hash));
    });

    test('returns null for non-existent file without throwing', () async {
      final result = await LinuxWallpaperThumbnailService.getThumbnailForWallpaper('/non/existent/file.jpg');
      expect(result, isNull);
    });

    test('returns null for corrupt image file without throwing', () async {
      final corruptFile = File('${tempDir.path}/corrupt.jpg');
      await corruptFile.writeAsString('not a valid image format at all');
      final result = await LinuxWallpaperThumbnailService.getThumbnailForWallpaper(corruptFile.path);
      expect(result, isNull);
    });
  });
}
