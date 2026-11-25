import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

class CacheService {
  /// Test hook to isolate cache operations during unit tests.
  static Directory? customCacheDir;

  static const String cacheSubdirName = 'homespace_cache';

  static Future<List<Directory>> _cacheDirectories({bool managedSubdirOnly = true}) async {
    if (customCacheDir != null) {
      return [customCacheDir!];
    }
    final dirs = <Directory>[];
    final seenPaths = <String>{};

    Future<void> addDir(Directory d) async {
      final target = managedSubdirOnly ? Directory('${d.path}/$cacheSubdirName') : d;
      String key = target.path;
      try {
        if (await target.exists()) {
          key = await target.resolveSymbolicLinks();
        }
      } catch (_) {}
      if (seenPaths.add(key)) {
        dirs.add(target);
      }
    }

    try {
      await addDir(await getTemporaryDirectory());
    } catch (_) {}
    try {
      await addDir(await getApplicationCacheDirectory());
    } catch (_) {}
    return dirs;
  }

  /// Returns and creates the isolated HomeSpace disk cache directory.
  static Future<Directory> getManagedCacheDirectory() async {
    if (customCacheDir != null) {
      if (!await customCacheDir!.exists()) {
        await customCacheDir!.create(recursive: true);
      }
      return customCacheDir!;
    }
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/$cacheSubdirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Calculate total size in bytes of HomeSpace disk cache without blocking UI isolate.
  static Future<int> getCacheSizeBytes() async {
    final dirs = await _cacheDirectories();
    var totalBytes = 0;
    for (final dir in dirs) {
      totalBytes += await _getDirectorySizeAsync(dir);
    }
    return totalBytes;
  }

  static Future<int> _getDirectorySizeAsync(Directory dir) async {
    var bytes = 0;
    try {
      if (!await dir.exists()) return 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            bytes += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return bytes;
  }

  /// Purges in-memory image caches and HomeSpace managed disk cache.
  static Future<int> clearCache() async {
    final reclaimed = await getCacheSizeBytes();

    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    final dirs = await _cacheDirectories();
    for (final dir in dirs) {
      try {
        if (await dir.exists()) {
          await for (final entity in dir.list(followLinks: false)) {
            try {
              await entity.delete(recursive: true);
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    return reclaimed;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
