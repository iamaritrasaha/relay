import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

class WallpaperThumbnailResult {
  final String path;
  final String hash;
  final int width;
  final int height;

  const WallpaperThumbnailResult({
    required this.path,
    required this.hash,
    required this.width,
    required this.height,
  });
}

/// Creates center-cropped, size-bounded JPEG thumbnails for Linux desktop wallpapers.
class LinuxWallpaperThumbnailService {
  const LinuxWallpaperThumbnailService._();

  static const int targetWidth = 1280;
  static const int targetHeight = 800;
  static const int maxByteSize = 1048576; // 1 MiB

  static WallpaperThumbnailResult? _cachedResult;
  static String? _cachedSourcePath;
  static DateTime? _cachedSourceMtime;

  static Future<WallpaperThumbnailResult?> getThumbnailForWallpaper(String sourcePath) async {
    try {
      final file = File(sourcePath);
      if (!file.existsSync()) return null;

      final stat = await file.stat();
      if (_cachedResult != null && _cachedSourcePath == sourcePath && _cachedSourceMtime == stat.modified) {
        return _cachedResult;
      }

      final result = await _processImage(file);
      if (result != null) {
        _cachedResult = result;
        _cachedSourcePath = sourcePath;
        _cachedSourceMtime = stat.modified;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<WallpaperThumbnailResult?> _processImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final srcW = decoded.width;
      final srcH = decoded.height;
      if (srcW <= 0 || srcH <= 0) return null;

      int cropW, cropH, cropX, cropY;
      if (srcW / srcH > targetWidth / targetHeight) {
        cropH = srcH;
        cropW = (srcH * targetWidth / targetHeight).round();
        cropX = (srcW - cropW) ~/ 2;
        cropY = 0;
      } else {
        cropW = srcW;
        cropH = (srcW * targetHeight / targetWidth).round();
        cropX = 0;
        cropY = (srcH - cropH) ~/ 2;
      }

      final cropped = img.copyCrop(decoded, x: cropX, y: cropY, width: cropW, height: cropH);

      int currentW = targetWidth;
      int currentH = targetHeight;
      var resized = img.copyResize(cropped, width: currentW, height: currentH, interpolation: img.Interpolation.linear);
      var jpegBytes = img.encodeJpg(resized, quality: 92);

      if (jpegBytes.length > maxByteSize) {
        jpegBytes = img.encodeJpg(resized, quality: 85);
      }
      if (jpegBytes.length > maxByteSize) {
        jpegBytes = img.encodeJpg(resized, quality: 75);
      }
      if (jpegBytes.length > maxByteSize) {
        currentW = 1024;
        currentH = 640;
        resized = img.copyResize(cropped, width: currentW, height: currentH, interpolation: img.Interpolation.linear);
        jpegBytes = img.encodeJpg(resized, quality: 80);
      }
      if (jpegBytes.length > maxByteSize) {
        jpegBytes = img.encodeJpg(resized, quality: 60);
      }
      if (jpegBytes.length > maxByteSize) {
        currentW = 800;
        currentH = 500;
        resized = img.copyResize(cropped, width: currentW, height: currentH, interpolation: img.Interpolation.linear);
        jpegBytes = img.encodeJpg(resized, quality: 70);
      }

      final hash = sha256.convert(jpegBytes).toString();
      final tempDir = Directory('${Directory.systemTemp.path}/relay_wallpaper');
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }
      final thumbFile = File('${tempDir.path}/thumb_$hash.jpg');
      if (!thumbFile.existsSync()) {
        await thumbFile.writeAsBytes(jpegBytes, flush: true);
      }

      return WallpaperThumbnailResult(
        path: thumbFile.path,
        hash: hash,
        width: currentW,
        height: currentH,
      );
    } catch (_) {
      return null;
    }
  }
}
