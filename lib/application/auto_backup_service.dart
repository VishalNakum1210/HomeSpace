import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

import '../data/http_remote_repositories.dart';
import '../domain/repositories.dart';
import 'device_media_service.dart';

class BackupFolderConfig {
  final String id;
  final String name;
  final String description;
  final List<String> paths;
  final bool enabled;
  final int? enabledAt;

  const BackupFolderConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.paths,
    this.enabled = true,
    this.enabledAt,
  });

  BackupFolderConfig copyWith({
    bool? enabled,
    int? enabledAt,
    bool clearEnabledAt = false,
  }) =>
      BackupFolderConfig(
        id: id,
        name: name,
        description: description,
        paths: paths,
        enabled: enabled ?? this.enabled,
        enabledAt: clearEnabledAt ? null : (enabledAt ?? this.enabledAt),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        if (enabledAt != null) 'enabledAt': enabledAt,
      };

  factory BackupFolderConfig.fromJson(
    Map<String, dynamic> json,
    BackupFolderConfig template,
  ) {
    return template.copyWith(
      enabled: json['enabled'] as bool? ?? template.enabled,
      enabledAt: (json['enabledAt'] as num?)?.toInt(),
    );
  }
}

class FreeUpSpaceResult {
  final int totalCount;
  final int totalBytes;
  final List<File> candidateFiles;

  const FreeUpSpaceResult({
    required this.totalCount,
    required this.totalBytes,
    required this.candidateFiles,
  });

  String get formattedSize {
    if (totalBytes < 1024 * 1024) {
      final kb = (totalBytes / 1024).toStringAsFixed(1);
      return '$kb KB';
    } else if (totalBytes < 1024 * 1024 * 1024) {
      final mb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
      return '$mb MB';
    } else {
      final gb = (totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
      return '$gb GB';
    }
  }
}

class AutoBackupService {
  static const List<BackupFolderConfig> defaultFolders = [
    BackupFolderConfig(
      id: 'camera',
      name: 'Camera (DCIM)',
      description: 'Photos captured by your phone camera',
      paths: [
        '/storage/emulated/0/DCIM/Camera',
        '/storage/emulated/0/DCIM',
      ],
      enabled: true,
    ),
    BackupFolderConfig(
      id: 'whatsapp',
      name: 'WhatsApp Images',
      description: 'Photos and videos received and sent via WhatsApp',
      paths: [
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images',
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',
        '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
        '/storage/emulated/0/WhatsApp/Media/WhatsApp Video',
      ],
      enabled: true,
    ),
    BackupFolderConfig(
      id: 'screenshots',
      name: 'Screenshots',
      description: 'Device screen captures',
      paths: [
        '/storage/emulated/0/Pictures/Screenshots',
        '/storage/emulated/0/DCIM/Screenshots',
      ],
      enabled: false,
    ),
    BackupFolderConfig(
      id: 'downloads',
      name: 'Downloads',
      description: 'Photos downloaded from web or apps',
      paths: [
        '/storage/emulated/0/Download',
      ],
      enabled: false,
    ),
    BackupFolderConfig(
      id: 'pictures',
      name: 'Pictures',
      description: 'Other gallery pictures and albums',
      paths: [
        '/storage/emulated/0/Pictures',
      ],
      enabled: false,
    ),
  ];

  @visibleForTesting
  static File? mockConfigFile;

  @visibleForTesting
  static File? mockDeletedSignaturesFile;

  static Future<File?> _getConfigFile() async {
    if (mockConfigFile != null) return mockConfigFile;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/homespace');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}/backup_settings.json');
    } catch (_) {
      return null;
    }
  }

  static Future<File?> _getDeletedSignaturesFile() async {
    if (mockDeletedSignaturesFile != null) return mockDeletedSignaturesFile;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/homespace');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}/deleted_signatures.json');
    } catch (_) {
      return null;
    }
  }

  static Set<String>? _deletedSignaturesCache;

  /// Loads and returns the set of lowercase filenames that have been deleted or trashed
  /// so that auto backup will never re-upload them.
  static Future<Set<String>> getDeletedSignatures() async {
    if (_deletedSignaturesCache != null) {
      return _deletedSignaturesCache!;
    }
    final signatures = <String>{};
    try {
      final file = await _getDeletedSignaturesFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content);
        if (list is List) {
          for (final item in list) {
            if (item is String && item.isNotEmpty) {
              signatures.add(item.toLowerCase().trim());
            }
          }
        }
      }
    } catch (_) {}

    // Cross-reference with native Android SharedPreferences
    try {
      final nativeIgnored = await DeviceMediaService.getIgnoredOrDeletedItems();
      signatures.addAll(nativeIgnored);
    } catch (_) {}

    _deletedSignaturesCache = signatures;
    return signatures;
  }

  /// Registers filenames as deleted so auto backup will permanently ignore them.
  static Future<void> markMediaDeleted(Iterable<String> filenames) async {
    final valid = filenames
        .map((s) => s.toLowerCase().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (valid.isEmpty) return;

    final current = await getDeletedSignatures();
    current.addAll(valid);
    _deletedSignaturesCache = current;

    try {
      final file = await _getDeletedSignaturesFile();
      if (file != null) {
        await file.writeAsString(jsonEncode(current.toList()), flush: true);
      }
    } catch (_) {}

    try {
      await DeviceMediaService.markMediaDeleted(valid);
    } catch (_) {}
  }

  /// Unregisters filenames from deleted signatures (e.g. if restored from Trash).
  static Future<void> unmarkMediaDeleted(Iterable<String> filenames) async {
    final valid = filenames
        .map((s) => s.toLowerCase().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (valid.isEmpty) return;

    final current = await getDeletedSignatures();
    current.removeAll(valid);
    _deletedSignaturesCache = current;

    try {
      final file = await _getDeletedSignaturesFile();
      if (file != null) {
        await file.writeAsString(jsonEncode(current.toList()), flush: true);
      }
    } catch (_) {}

    try {
      await DeviceMediaService.unmarkMediaDeleted(valid);
    } catch (_) {}
  }

  static Future<List<BackupFolderConfig>> loadFolders() async {
    try {
      final startTime = await getBackupStartTime();
      final file = await _getConfigFile();
      if (file == null || !file.existsSync()) {
        return defaultFolders.map((template) {
          return template.copyWith(
            enabledAt: template.enabled ? startTime : null,
          );
        }).toList();
      }
      final raw = file.readAsStringSync();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final folderList = (map['folders'] as List<dynamic>?) ?? [];

      return defaultFolders.map((template) {
        final found = folderList.firstWhere(
          (item) => item is Map && item['id'] == template.id,
          orElse: () => null,
        );
        if (found is Map<String, dynamic>) {
          final config = BackupFolderConfig.fromJson(found, template);
          if (config.enabled && (config.enabledAt == null || config.enabledAt! <= 0)) {
            return config.copyWith(enabledAt: startTime);
          }
          return config;
        }
        return template.copyWith(
          enabledAt: template.enabled ? startTime : null,
        );
      }).toList();
    } catch (_) {
      return defaultFolders;
    }
  }

  static Future<int> getBackupStartTime() async {
    try {
      final file = await _getConfigFile();
      if (file != null && file.existsSync()) {
        final raw = file.readAsStringSync();
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final start = map['backupStartTime'] as num?;
        if (start != null && start > 0) return start.toInt();
      }
    } catch (_) {}
    final now = DateTime.now().millisecondsSinceEpoch;
    await setBackupStartTime(now);
    return now;
  }

  static Future<void> setBackupStartTime(int timestamp) async {
    try {
      final file = await _getConfigFile();
      if (file == null) return;
      Map<String, dynamic> map = {};
      if (file.existsSync()) {
        try {
          map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {}
      }
      map['backupStartTime'] = timestamp;
      file.writeAsStringSync(jsonEncode(map), flush: true);
    } catch (_) {}
  }

  static Future<bool> isWifiOnly() async {
    try {
      final file = await _getConfigFile();
      if (file != null && file.existsSync()) {
        final raw = file.readAsStringSync();
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return map['wifiOnly'] as bool? ?? false;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> setWifiOnly(bool enabled) async {
    try {
      final file = await _getConfigFile();
      if (file == null) return;
      Map<String, dynamic> map = {};
      if (file.existsSync()) {
        try {
          map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {}
      }
      map['wifiOnly'] = enabled;
      file.writeAsStringSync(jsonEncode(map), flush: true);
      await syncConfigToNative();
    } catch (_) {}
  }

  static Future<bool> isRequireCharging() async {
    try {
      final file = await _getConfigFile();
      if (file != null && file.existsSync()) {
        final raw = file.readAsStringSync();
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return map['requireCharging'] as bool? ?? false;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> setRequireCharging(bool enabled) async {
    try {
      final file = await _getConfigFile();
      if (file == null) return;
      Map<String, dynamic> map = {};
      if (file.existsSync()) {
        try {
          map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {}
      }
      map['requireCharging'] = enabled;
      file.writeAsStringSync(jsonEncode(map), flush: true);
      await syncConfigToNative();
    } catch (_) {}
  }

  static Future<bool> hasInitialChoiceMade() async {
    try {
      final file = await _getConfigFile();
      if (file != null && file.existsSync()) {
        final raw = file.readAsStringSync();
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return map['initialChoiceMade'] as bool? ?? false;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> setInitialChoiceMade(bool made) async {
    try {
      final file = await _getConfigFile();
      if (file == null) return;
      Map<String, dynamic> map = {};
      if (file.existsSync()) {
        try {
          map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {}
      }
      map['initialChoiceMade'] = made;
      file.writeAsStringSync(jsonEncode(map), flush: true);
    } catch (_) {}
  }

  static Future<void> saveFolders(List<BackupFolderConfig> folders) async {
    try {
      final startTime = await getBackupStartTime();
      final wifiOnly = await isWifiOnly();
      final charging = await isRequireCharging();
      final file = await _getConfigFile();
      if (file != null) {
        Map<String, dynamic> map = {};
        if (file.existsSync()) {
          try {
            map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          } catch (_) {}
        }
        map['folders'] = folders.map((f) => f.toJson()).toList();
        map['backupStartTime'] = startTime;
        map['wifiOnly'] = wifiOnly;
        map['requireCharging'] = charging;
        file.writeAsStringSync(jsonEncode(map), flush: true);
      }
      final enabledFolders = folders.where((f) => f.enabled).toList();
      final enabledIds = enabledFolders.map((f) => f.id).toList();
      final folderStartTimes = <String, int>{
        for (final f in enabledFolders)
          if (f.enabledAt != null && f.enabledAt! > 0) f.id: f.enabledAt!,
      };
      await DeviceMediaService.syncBackupConfig(
        enabledFolders: enabledIds,
        folderStartTimes: folderStartTimes,
        backupStartTime: startTime,
        wifiOnly: wifiOnly,
        requireCharging: charging,
      );
    } catch (_) {}
  }

  /// Synchronizes current backup configuration and credentials to Native Android background service.
  static Future<void> syncConfigToNative({
    String? serverUri,
    String? token,
    Map<String, String>? trustedCertPins,
  }) async {
    try {
      final folders = await loadFolders();
      final startTime = await getBackupStartTime();
      final wifiOnly = await isWifiOnly();
      final charging = await isRequireCharging();
      final enabledFolders = folders.where((f) => f.enabled).toList();
      final enabledIds = enabledFolders.map((f) => f.id).toList();
      final folderStartTimes = <String, int>{
        for (final f in enabledFolders)
          if (f.enabledAt != null && f.enabledAt! > 0) f.id: f.enabledAt!,
      };
      await DeviceMediaService.syncBackupConfig(
        serverUri: serverUri,
        token: token,
        enabledFolders: enabledIds,
        folderStartTimes: folderStartTimes,
        backupStartTime: startTime,
        wifiOnly: wifiOnly,
        requireCharging: charging,
        trustedCertPins: trustedCertPins,
      );
    } catch (_) {}
  }

  static Directory? findActiveFolder(BackupFolderConfig config) {
    for (final path in config.paths) {
      final dir = Directory(path);
      if (dir.existsSync()) return dir;
    }
    return null;
  }

  static Future<Directory?> findActiveFolderAsync(BackupFolderConfig config) async {
    for (final path in config.paths) {
      final dir = Directory(path);
      if (await dir.exists()) return dir;
    }
    return null;
  }

  static int countPhotosInFolder(BackupFolderConfig config) {
    var count = 0;
    for (final path in config.paths) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      try {
        count += dir
            .listSync(recursive: false, followLinks: false)
            .whereType<File>()
            .where((f) => _isSupportedMedia(f.path))
            .length;
      } catch (_) {}
    }
    return count;
  }

  static Future<int> countPhotosInFolderAsync(BackupFolderConfig config) async {
    var count = 0;
    for (final path in config.paths) {
      final dir = Directory(path);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: false, followLinks: false)) {
          if (entity is File && _isSupportedMedia(entity.path)) {
            count++;
          }
        }
      } catch (_) {}
    }
    return count;
  }

  static bool _isSupportedMedia(String filePath) {
    final lower = filePath.toLowerCase().replaceAll('\\', '/');
    final filename = lower.split('/').last;
    if (filename.startsWith('.') || filename.contains('.trashed') || filename.contains('.pending')) {
      return false;
    }
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv');
  }

  /// Categorizes a file path into its specific backup folder ID (e.g. 'camera', 'whatsapp', 'screenshots', 'downloads', 'pictures'),
  /// or null if it does not belong to any recognized backup folder or is an app-internal path.
  static String? classifyMediaFolder(String filePath) {
    final lower = filePath.toLowerCase().replaceAll('\\', '/');

    // Never backup hidden or OS-trashed files
    final filename = lower.split('/').last;
    if (filename.startsWith('.') || filename.contains('.trashed') || filename.contains('.pending')) {
      return null;
    }

    // Never backup HomeSpace downloaded photos/videos to prevent re-upload loops
    if (lower.contains('/pictures/homespace') || lower.contains('/movies/homespace')) {
      return null;
    }

    // 1. Screenshots (takes precedence over DCIM or Pictures)
    if (lower.contains('/screenshots') ||
        lower.contains('/screenshot') ||
        lower.split('/').last.startsWith('screenshot')) {
      return 'screenshots';
    }

    // 2. WhatsApp Images and Videos
    if (lower.contains('whatsapp')) {
      return 'whatsapp';
    }

    // 3. Downloads
    if (lower.contains('/download') || lower.contains('/downloads')) {
      return 'downloads';
    }

    // 4. Camera (DCIM)
    if (lower.contains('/dcim/camera') ||
        lower.contains('/dcim/100andro') ||
        lower.contains('/dcim/100media') ||
        (lower.contains('/dcim') && !lower.contains('/dcim/facebook') && !lower.contains('/dcim/restored'))) {
      return 'camera';
    }

    // 5. Pictures
    if (lower.contains('/pictures')) {
      return 'pictures';
    }

    return null;
  }

  static Future<int> scanAndQueueBackup({
    required List<BackupFolderConfig> folders,
    required HomeRepository repository,
    bool onlyNewPhotos = false,
    int? minTimestampMs,
  }) async {
    final uploadRepo = repository.uploads;
    if (uploadRepo is! HttpUploadRepository) return 0;

    final defaultMinTime = onlyNewPhotos ? (minTimestampMs ?? await getBackupStartTime()) : 0;

    // Check & request storage permission if running on Android
    final hasPerm = await DeviceMediaService.checkStoragePermission();
    if (!hasPerm) {
      final granted = await DeviceMediaService.requestStoragePermission();
      if (!granted) return 0;
    }

    final folderMap = {for (final f in folders) f.id: f};
    final enabledFolderIds = folders
        .where((f) => f.enabled)
        .map((f) => f.id)
        .toSet();

    if (enabledFolderIds.isEmpty) return 0;

    final activeTitles = repository.media.map((m) => m.title.toLowerCase()).toSet();
    final trashedIds = repository.trash.map((t) => t.mediaId).toSet();
    final trashedTitles = repository.snapshot.media
        .where((m) => trashedIds.contains(m.id))
        .map((m) => m.title.toLowerCase())
        .toSet();
    final queuedTitles = repository.uploads.items
        .map((u) => (u.title ?? '').toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet();
    final deletedSignatures = await getDeletedSignatures();

    final existingTitles = {
      ...activeTitles,
      ...trashedTitles,
      ...queuedTitles,
      ...deletedSignatures,
    };

    int queuedCount = 0;

    // 1. Query native Android MediaStore
    try {
      final cameraMedia = await DeviceMediaService.queryCameraMedia();
      for (final item in cameraMedia) {
        final path = item['path'] as String?;
        final filename = item['name'] as String? ?? 'media.jpg';
        final mimeType = item['mimeType'] as String? ?? 'image/jpeg';
        if (path == null) continue;
        if (filename.startsWith('.') || filename.toLowerCase().contains('.trashed') || filename.toLowerCase().contains('.pending')) {
          continue;
        }

        // Strictly verify that this file belongs to an enabled folder
        final folderId = classifyMediaFolder(path);
        if (folderId == null || !enabledFolderIds.contains(folderId)) {
          continue;
        }

        final folderConfig = folderMap[folderId];
        if (folderConfig == null || !folderConfig.enabled) continue;

        if (existingTitles.contains(filename.toLowerCase())) continue;

        final file = File(path);
        if (!file.existsSync()) continue;

        final dateTakenMs = item['dateTaken'] as num?;
        final takenAt = dateTakenMs != null && dateTakenMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(dateTakenMs.toInt())
            : (file.existsSync() ? file.lastModifiedSync() : DateTime.now());

        // When onlyNewPhotos is true, skip media created before this folder's backup was started
        final folderMinTime = minTimestampMs ?? folderConfig.enabledAt ?? defaultMinTime;
        if (onlyNewPhotos && folderMinTime > 0 && takenAt.millisecondsSinceEpoch < folderMinTime) {
          continue;
        }

        final fileSize = file.lengthSync();
        if (fileSize <= 0) continue;

        final uploadId = 'backup-${DateTime.now().microsecondsSinceEpoch}-$queuedCount';
        uploadRepo.queueUpload(
          id: uploadId,
          mediaId: uploadId,
          totalBytes: fileSize,
          filePath: file.path,
          filename: filename,
          mimeType: mimeType,
          takenAt: takenAt,
        );

        existingTitles.add(filename.toLowerCase());
        queuedCount++;
      }
    } catch (_) {}

    // 2. Scan specific folders asynchronously (for non-Android or multi-path folders like WhatsApp Images + Video)
    for (final config in folders) {
      if (!config.enabled) continue;

      for (final folderPath in config.paths) {
        final dir = Directory(folderPath);
        if (!await dir.exists()) continue;

        try {
          await for (final entity in dir.list(recursive: false, followLinks: false)) {
            if (entity is! File) continue;
            if (!_isSupportedMedia(entity.path)) continue;

            final folderId = classifyMediaFolder(entity.path) ?? config.id;
            if (!enabledFolderIds.contains(folderId)) continue;

            final folderConfig = folderMap[folderId] ?? config;
            if (!folderConfig.enabled) continue;

            final filename = entity.uri.pathSegments.lastWhere(
              (p) => p.isNotEmpty,
              orElse: () => 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
            );

            if (filename.startsWith('.') ||
                filename.toLowerCase().contains('.trashed') ||
                filename.toLowerCase().contains('.pending')) {
              continue;
            }

            if (existingTitles.contains(filename.toLowerCase())) continue;

            final stat = await entity.stat();
            final fileSize = stat.size;
            if (fileSize <= 0) continue;
            final takenAt = stat.modified;
            final folderMinTime = minTimestampMs ?? folderConfig.enabledAt ?? defaultMinTime;
            if (onlyNewPhotos && folderMinTime > 0 && takenAt.millisecondsSinceEpoch < folderMinTime) {
              continue;
            }

            final isVideo = filename.toLowerCase().endsWith('.mp4') ||
                filename.toLowerCase().endsWith('.mov') ||
                filename.toLowerCase().endsWith('.webm') ||
                filename.toLowerCase().endsWith('.mkv');
            final mimeType = lookupMimeType(filename) ?? (isVideo ? 'video/mp4' : 'image/jpeg');
            final uploadId = 'backup-${DateTime.now().microsecondsSinceEpoch}-$queuedCount';

            uploadRepo.queueUpload(
              id: uploadId,
              mediaId: uploadId,
              totalBytes: fileSize,
              filePath: entity.path,
              filename: filename,
              mimeType: mimeType,
              takenAt: takenAt,
            );

            existingTitles.add(filename.toLowerCase());
            queuedCount++;
          }
        } catch (_) {}
      }
    }

    return queuedCount;
  }

  static Future<int> triggerAutoBackupIfEnabled({
    required HomeRepository repository,
  }) async {
    try {
      final wifiOnly = await isWifiOnly();
      if (wifiOnly && !await DeviceMediaService.isWifiConnected()) {
        return 0;
      }
      final chargingOnly = await isRequireCharging();
      if (chargingOnly && !await DeviceMediaService.isDeviceCharging()) {
        return 0;
      }

      final folders = await loadFolders();
      if (!folders.any((f) => f.enabled)) return 0;
      return await scanAndQueueBackup(
        folders: folders,
        repository: repository,
        onlyNewPhotos: true,
      );
    } catch (_) {
      return 0;
    }
  }

  /// Calculates how many local device media files are already confirmed backed up on the HomeSpace server,
  /// returning the candidate files, total count, and total byte size that can be safely freed up.
  static Future<FreeUpSpaceResult> calculateFreeUpSpace({
    required List<BackupFolderConfig> folders,
    required HomeRepository repository,
  }) async {
    final candidateFiles = <File>[];
    final seenPaths = <String>{};
    int totalBytes = 0;

    final syncedMedia = repository.media.where((m) => m.isSynced).toList();
    if (syncedMedia.isEmpty) {
      return const FreeUpSpaceResult(totalCount: 0, totalBytes: 0, candidateFiles: []);
    }

    final syncedByTitle = <String, List<int?>>{};
    for (final m in syncedMedia) {
      final key = m.title.toLowerCase().trim();
      if (key.isNotEmpty) {
        (syncedByTitle[key] ??= <int?>[]).add(m.sizeBytes);
      }
    }

    final deletedSignatures = await getDeletedSignatures();

    void tryAddCandidate(File file, String lowerName, int size) {
      if (lowerName.isEmpty || size <= 0) return;
      if (deletedSignatures.contains(lowerName)) return;
      final sizes = syncedByTitle[lowerName];
      if (sizes == null) return;
      // Match exact byte size if server reported it, or filename match if size wasn't recorded.
      final matches = sizes.any((s) => s == null || s == size);
      if (!matches) return;
      if (seenPaths.add(file.path)) {
        totalBytes += size;
        candidateFiles.add(file);
      }
    }

    // Check MediaStore first on Android
    try {
      final cameraMedia = await DeviceMediaService.queryCameraMedia();
      for (final item in cameraMedia) {
        final p = item['path'] as String?;
        final name = (item['name'] as String? ?? '').toLowerCase().trim();
        final size = (item['size'] as num?)?.toInt() ?? 0;
        if (p != null && p.isNotEmpty && name.isNotEmpty && classifyMediaFolder(p) != null) {
          final file = File(p);
          if (await file.exists()) {
            tryAddCandidate(file, name, size > 0 ? size : (await file.length()));
          }
        }
      }
    } catch (_) {}

    // Check configured folder paths asynchronously
    for (final config in folders) {
      for (final folderPath in config.paths) {
        final dir = Directory(folderPath);
        if (!await dir.exists()) continue;

        try {
          await for (final entity in dir.list(recursive: false, followLinks: false)) {
            if (entity is! File) continue;
            final filename = entity.uri.pathSegments.isNotEmpty
                ? entity.uri.pathSegments.last
                : '';
            final lowerName = filename.toLowerCase().trim();
            int size = 0;
            try {
              size = await entity.length();
            } catch (_) {}
            tryAddCandidate(entity, lowerName, size);
          }
        } catch (_) {}
      }
    }

    return FreeUpSpaceResult(
      totalCount: candidateFiles.length,
      totalBytes: totalBytes,
      candidateFiles: candidateFiles,
    );
  }

  /// Safely removes backed-up local files from device storage, returning both deleted file count and freed bytes.
  static Future<({int deletedCount, int freedBytes})> freeUpSpaceDetailed({
    required List<File> files,
  }) async {
    int freed = 0;
    int count = 0;
    for (final file in files) {
      try {
        if (await file.exists()) {
          final size = await file.length();
          final deleted = await DeviceMediaService.deleteDeviceFile(file.path);
          if (deleted || !await file.exists()) {
            freed += size;
            count++;
          }
        }
      } catch (_) {}
    }
    return (deletedCount: count, freedBytes: freed);
  }

  /// Safely removes backed-up local files from device storage, returning freed bytes.
  static Future<int> freeUpSpace({
    required List<File> files,
  }) async {
    final res = await freeUpSpaceDetailed(files: files);
    return res.freedBytes;
  }
}
