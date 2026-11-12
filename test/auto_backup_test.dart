import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/application/auto_backup_service.dart';
import 'package:homespace/application/device_media_service.dart';
import 'package:homespace/application/home_scope.dart';
import 'package:homespace/data/http_remote_repositories.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/pages/backup_settings_page.dart';

void main() {
  test('AutoBackupService defaultFolders contains Camera and WhatsApp', () {
    final folders = AutoBackupService.defaultFolders;
    expect(folders.any((f) => f.id == 'camera'), isTrue);
    expect(folders.any((f) => f.id == 'whatsapp'), isTrue);
    expect(folders.any((f) => f.id == 'screenshots'), isTrue);

    final camera = folders.firstWhere((f) => f.id == 'camera');
    expect(camera.enabled, isTrue);

    final toggled = camera.copyWith(enabled: false);
    expect(toggled.enabled, isFalse);

    final json = toggled.toJson();
    expect(json['id'], 'camera');
    expect(json['enabled'], isFalse);
  });

  testWidgets('BackupSettingsPage renders folder list and Scan button', (tester) async {
    final repository = LocalHomeRepository(
      store: MemorySnapshotStore(),
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      HomeScope(
        repository: repository,
        child: const MaterialApp(
          home: BackupSettingsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Auto-backup folders'), findsOneWidget);
    expect(find.text('Camera (DCIM)'), findsOneWidget);
    expect(find.text('WhatsApp Images'), findsOneWidget);
    expect(find.text('Screenshots'), findsOneWidget);

    // Toggle switch
    final switches = find.byType(Switch);
    expect(switches, findsWidgets);
    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    // Scroll to scan button
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('scan-backup-now')),
      200,
    );
    await tester.pumpAndSettle();

    expect(find.text('Scan & Backup Now'), findsOneWidget);
    expect(find.text('View Upload Queue'), findsOneWidget);

    // Tap Scan button
    await tester.tap(find.byKey(const ValueKey('scan-backup-now')));
    await tester.pumpAndSettle();
  });

  group('AutoBackupService folder classification & filtering', () {
    test('classifyMediaFolder categorizes paths into specific folders', () {
      expect(
        AutoBackupService.classifyMediaFolder('/storage/emulated/0/DCIM/Camera/IMG_20261111.jpg'),
        'camera',
      );
      expect(
        AutoBackupService.classifyMediaFolder('/storage/emulated/0/DCIM/Camera/VID_20261111.mp4'),
        'camera',
      );
      expect(
        AutoBackupService.classifyMediaFolder('/storage/emulated/0/DCIM/100ANDRO/DSC_0001.jpg'),
        'camera',
      );
      expect(
        AutoBackupService.classifyMediaFolder('/storage/emulated/0/Pictures/Screenshots/Screenshot_01.png'),
        'screenshots',
      );
      expect(
        AutoBackupService.classifyMediaFolder('/storage/emulated/0/DCIM/Screenshots/Screenshot_02.png'),
        'screenshots',
      );
      expect(
        AutoBackupService.classifyMediaFolder('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/WA_01.jpg'),
        'whatsapp',
      );
      expect(
        AutoBackupService.classifyMediaFolder('/storage/emulated/0/Download/wallpaper.jpg'),
        'downloads',
      );
      expect(
        AutoBackupService.classifyMediaFolder('/storage/emulated/0/Pictures/family.jpg'),
        'pictures',
      );
      expect(
        AutoBackupService.classifyMediaFolder('/storage/emulated/0/Pictures/HomeSpace/saved.jpg'),
        isNull,
      );
    });

    test('scanAndQueueBackup strictly queues only camera media when only camera is enabled', () async {
      DeviceMediaService.debugOverrideIsAndroid = true;
      addTearDown(() => DeviceMediaService.debugOverrideIsAndroid = false);

      final tempDir = Directory.systemTemp.createTempSync('backup_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final cameraFile = File('${tempDir.path}/DCIM/Camera/IMG_01.jpg')..createSync(recursive: true);
      cameraFile.writeAsBytesSync([1, 2, 3]);

      final screenshotFile = File('${tempDir.path}/Pictures/Screenshots/Screenshot_01.png')..createSync(recursive: true);
      screenshotFile.writeAsBytesSync([4, 5, 6]);

      final whatsappFile = File('${tempDir.path}/WhatsApp/WA_01.jpg')..createSync(recursive: true);
      whatsappFile.writeAsBytesSync([7, 8, 9]);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.homespace.homespace/permissions'),
        (call) async {
          if (call.method == 'checkStoragePermission') return true;
          if (call.method == 'requestStoragePermission') return true;
          if (call.method == 'queryCameraMedia') {
            return [
              {
                'path': cameraFile.path,
                'name': 'IMG_01.jpg',
                'size': 3,
                'mimeType': 'image/jpeg',
                'isVideo': false,
              },
              {
                'path': screenshotFile.path,
                'name': 'Screenshot_01.png',
                'size': 3,
                'mimeType': 'image/png',
                'isVideo': false,
              },
              {
                'path': whatsappFile.path,
                'name': 'WA_01.jpg',
                'size': 3,
                'mimeType': 'image/jpeg',
                'isVideo': false,
              },
            ];
          }
          return null;
        },
      );

      final uploadRepo = HttpUploadRepository(
        getServerAddress: () => Uri.parse('http://127.0.0.1:8080'),
        getAuthToken: () => 'token',
      );

      final repository = LocalHomeRepository(
        store: MemorySnapshotStore(),
        customUploads: uploadRepo,
      );
      addTearDown(repository.dispose);

      // ONLY camera is enabled, screenshots and whatsapp are disabled
      final folders = [
        const BackupFolderConfig(
          id: 'camera',
          name: 'Camera',
          description: '',
          paths: [],
          enabled: true,
        ),
        const BackupFolderConfig(
          id: 'screenshots',
          name: 'Screenshots',
          description: '',
          paths: [],
          enabled: false,
        ),
        const BackupFolderConfig(
          id: 'whatsapp',
          name: 'WhatsApp',
          description: '',
          paths: [],
          enabled: false,
        ),
      ];

      final queued = await AutoBackupService.scanAndQueueBackup(
        folders: folders,
        repository: repository,
      );

      expect(queued, 1);
      expect(uploadRepo.items.length, 1);
      expect(uploadRepo.items.first.title, 'IMG_01.jpg');
    });
  });
}
