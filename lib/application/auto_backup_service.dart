import 'dart:convert';
import 'dart:io';
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

  const BackupFolderConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.paths,
    this.enabled = true,
  });

  BackupFolderConfig copyWith({bool? enabled}) => BackupFolderConfig(
        id: id,
        name: name,
        description: description,
        paths: paths,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
      };

  factory BackupFolderConfig.fromJson(
    Map<String, dynamic> json,
    BackupFolderConfig template,
  ) {
    return template.copyWith(
      enabled: json['enabled'] as bool? ?? template.enabled,
    );
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
      description: 'Images received and sent via WhatsApp',
      paths: [
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images',
        '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
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

  static Future<File?> _getConfigFile() async {
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

  static Future<List<BackupFolderConfig>> loadFolders() async {
    try {
      final file = await _getConfigFile();
      if (file == null || !await file.exists()) return defaultFolders;
      final raw = await file.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final folderList = (map['folders'] as List<dynamic>?) ?? [];

      return defaultFolders.map((template) {
        final found = folderList.firstWhere(
          (item) => item is Map && item['id'] == template.id,
          orElse: () => null,
        );
        if (found is Map<String, dynamic>) {
          return BackupFolderConfig.fromJson(found, template);
        }
        return template;
      }).toList();
    } catch (_) {
      return defaultFolders;
    }
  }

  static Future<void> saveFolders(List<BackupFolderConfig> folders) async {
    try {
      final file = await _getConfigFile();
      if (file == null) return;
      final data = {
        'folders': folders.map((f) => f.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Directory? findActiveFolder(BackupFolderConfig config) {
    for (final path in config.paths) {
      final dir = Directory(path);
      if (dir.existsSync()) return dir;
    }
    return null;
  }

  static int countPhotosInFolder(BackupFolderConfig config) {
    final dir = findActiveFolder(config);
    if (dir == null) return 0;
    try {
      return dir
          .listSync(recursive: false, followLinks: false)
          .whereType<File>()
          .where((f) => _isSupportedMedia(f.path))
          .length;
    } catch (_) {
      return 0;
    }
  }

  static bool _isSupportedMedia(String filePath) {
    final lower = filePath.toLowerCase();
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

  static Future<int> scanAndQueueBackup({
    required List<BackupFolderConfig> folders,
    required HomeRepository repository,
  }) async {
    final uploadRepo = repository.uploads;
    if (uploadRepo is! HttpUploadRepository) return 0;

    // Check & request storage permission if running on Android
    final hasPerm = await DeviceMediaService.checkStoragePermission();
    if (!hasPerm) {
      final granted = await DeviceMediaService.requestStoragePermission();
      if (!granted) return 0;
    }

    final existingTitles = {
      ...repository.media.map((m) => m.title.toLowerCase()),
      ...repository.uploads.items.map((u) => (u.title ?? '').toLowerCase()),
    };

    int queuedCount = 0;

    // 1. If Camera folder is enabled, query native Android MediaStore
    final cameraEnabled = folders.any((f) => f.id == 'camera' && f.enabled);
    if (cameraEnabled) {
      try {
        final cameraMedia = await DeviceMediaService.queryCameraMedia();
        for (final item in cameraMedia) {
          final path = item['path'] as String?;
          final filename = item['name'] as String? ?? 'media.jpg';
          final mimeType = item['mimeType'] as String? ?? 'image/jpeg';
          if (path == null) continue;
          if (existingTitles.contains(filename.toLowerCase())) continue;

          final file = File(path);
          if (!file.existsSync()) continue;
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) continue;

          final uploadId = 'backup-${DateTime.now().microsecondsSinceEpoch}-$queuedCount';
          uploadRepo.queueUpload(
            id: uploadId,
            mediaId: uploadId,
            totalBytes: bytes.length,
            bytes: bytes,
            filename: filename,
            mimeType: mimeType,
          );

          existingTitles.add(filename.toLowerCase());
          queuedCount++;
        }
      } catch (_) {}
    }

    // 2. Scan specific folders (WhatsApp, Screenshots, Downloads, Pictures, etc.)
    for (final config in folders) {
      if (!config.enabled) continue;
      if (config.id == 'camera' && queuedCount > 0) continue;

      final dir = findActiveFolder(config);
      if (dir == null) continue;

      try {
        final entities = dir.listSync(recursive: false, followLinks: false);
        for (final entity in entities) {
          if (entity is! File) continue;
          if (!_isSupportedMedia(entity.path)) continue;

          final filename = entity.uri.pathSegments.lastWhere(
            (p) => p.isNotEmpty,
            orElse: () => 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );

          if (existingTitles.contains(filename.toLowerCase())) continue;

          final bytes = await entity.readAsBytes();
          final isVideo = filename.toLowerCase().endsWith('.mp4') ||
              filename.toLowerCase().endsWith('.mov') ||
              filename.toLowerCase().endsWith('.webm');
          final mimeType = lookupMimeType(filename) ?? (isVideo ? 'video/mp4' : 'image/jpeg');
          final uploadId = 'backup-${DateTime.now().microsecondsSinceEpoch}-$queuedCount';

          uploadRepo.queueUpload(
            id: uploadId,
            mediaId: uploadId,
            totalBytes: bytes.length,
            bytes: bytes,
            filename: filename,
            mimeType: mimeType,
          );

          existingTitles.add(filename.toLowerCase());
          queuedCount++;
        }
      } catch (_) {}
    }

    return queuedCount;
  }

  static Future<int> triggerAutoBackupIfEnabled({
    required HomeRepository repository,
  }) async {
    try {
      final folders = await loadFolders();
      if (!folders.any((f) => f.enabled)) return 0;
      return await scanAndQueueBackup(folders: folders, repository: repository);
    } catch (_) {
      return 0;
    }
  }
}
