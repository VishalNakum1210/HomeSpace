import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

class CacheService {
  /// Test hook to isolate cache operations during unit tests.
  static Directory? customCacheDir;

  /// Calculate the total size in bytes of files in temporary and application cache directories.
  static Future<int> getCacheSizeBytes() async {
    if (customCacheDir != null) {
      return _getDirectorySize(customCacheDir!);
    }

    var totalBytes = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      totalBytes += _getDirectorySize(tempDir);
    } catch (_) {}

    try {
      final cacheDir = await getApplicationCacheDirectory();
      totalBytes += _getDirectorySize(cacheDir);
    } catch (_) {}

    return totalBytes;
  }

  static int _getDirectorySize(Directory dir) {
    var bytes = 0;
    if (!dir.existsSync()) return 0;
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            bytes += entity.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return bytes;
  }

  /// Purges temporary images, previews, and thumbnails while preserving SQLite databases and user session.
  static Future<int> clearCache() async {
    final reclaimed = await getCacheSizeBytes();

    // 1. Clear in-memory Flutter image caches
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    if (customCacheDir != null) {
      try {
        if (customCacheDir!.existsSync()) {
          for (final entity in customCacheDir!.listSync(followLinks: false)) {
            try {
              entity.deleteSync(recursive: true);
            } catch (_) {}
          }
        }
      } catch (_) {}
      return reclaimed;
    }

    // 2. Clear disk temporary directory
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        for (final entity in tempDir.listSync(followLinks: false)) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 3. Clear disk cache directory
    try {
      final cacheDir = await getApplicationCacheDirectory();
      if (cacheDir.existsSync()) {
        for (final entity in cacheDir.listSync(followLinks: false)) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}

    return reclaimed;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
