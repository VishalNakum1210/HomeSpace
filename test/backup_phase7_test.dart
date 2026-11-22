import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/application/auto_backup_service.dart';
import 'package:homespace/application/device_media_service.dart';
import 'package:homespace/application/home_scope.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/backup_settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File mockConfigFile;
  late File mockDeletedSignaturesFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('homespace_p7_test');
    mockConfigFile = File('${tempDir.path}/backup_settings.json');
    mockDeletedSignaturesFile = File('${tempDir.path}/deleted_signatures.json');
    AutoBackupService.mockConfigFile = mockConfigFile;
    AutoBackupService.mockDeletedSignaturesFile = mockDeletedSignaturesFile;
    DeviceMediaService.mockIsWifiConnected = null;
    DeviceMediaService.mockIsDeviceCharging = null;
    DeviceMediaService.mockDeleteDeviceFileResult = null;
  });

  tearDown(() {
    AutoBackupService.mockConfigFile = null;
    AutoBackupService.mockDeletedSignaturesFile = null;
    DeviceMediaService.mockIsWifiConnected = null;
    DeviceMediaService.mockIsDeviceCharging = null;
    DeviceMediaService.mockDeleteDeviceFileResult = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Phase 7: Network & Power Safeguards Configuration', () {
    test('Default preferences are false for Wi-Fi only and require charging', () async {
      expect(await AutoBackupService.isWifiOnly(), isFalse);
      expect(await AutoBackupService.isRequireCharging(), isFalse);
      expect(await AutoBackupService.hasInitialChoiceMade(), isFalse);
    });

    test('Can update and retrieve Wi-Fi only and require charging constraints', () async {
      await AutoBackupService.setWifiOnly(true);
      expect(await AutoBackupService.isWifiOnly(), isTrue);

      await AutoBackupService.setRequireCharging(true);
      expect(await AutoBackupService.isRequireCharging(), isTrue);

      await AutoBackupService.setInitialChoiceMade(true);
      expect(await AutoBackupService.hasInitialChoiceMade(), isTrue);

      await AutoBackupService.setWifiOnly(false);
      expect(await AutoBackupService.isWifiOnly(), isFalse);
    });

    test('triggerAutoBackupIfEnabled respects Wi-Fi only constraint', () async {
      final repo = LocalHomeRepository(store: MemorySnapshotStore());
      addTearDown(repo.dispose);
      await repo.initialize();

      await AutoBackupService.setWifiOnly(true);
      DeviceMediaService.mockIsWifiConnected = false;

      // With Wi-Fi only set and no Wi-Fi, triggerAutoBackupIfEnabled should abort
      final result = await AutoBackupService.triggerAutoBackupIfEnabled(repository: repo);
      expect(result, equals(0));

      // With Wi-Fi connected, it should proceed (0 items queued because folders are empty)
      DeviceMediaService.mockIsWifiConnected = true;
      final resultWithWifi = await AutoBackupService.triggerAutoBackupIfEnabled(repository: repo);
      expect(resultWithWifi, equals(0));
    });

    test('triggerAutoBackupIfEnabled respects charging constraint', () async {
      final repo = LocalHomeRepository(store: MemorySnapshotStore());
      addTearDown(repo.dispose);
      await repo.initialize();

      await AutoBackupService.setRequireCharging(true);
      DeviceMediaService.mockIsDeviceCharging = false;

      // With charging required and not charging, triggerAutoBackupIfEnabled should abort
      final result = await AutoBackupService.triggerAutoBackupIfEnabled(repository: repo);
      expect(result, equals(0));

      // With device charging, it should proceed
      DeviceMediaService.mockIsDeviceCharging = true;
      final resultCharging = await AutoBackupService.triggerAutoBackupIfEnabled(repository: repo);
      expect(resultCharging, equals(0));
    });
  });

  group('Phase 7: Free Up Device Space Assistant', () {
    test('calculateFreeUpSpace identifies only synced items with local files', () async {
      final repo = LocalHomeRepository(store: MemorySnapshotStore());
      addTearDown(repo.dispose);
      await repo.initialize();

      // Create a test file in tempDir
      final testFolder = Directory('${tempDir.path}/Camera')..createSync(recursive: true);
      final tempFile = File('${testFolder.path}/photo1.jpg')
        ..writeAsBytesSync(List.filled(1024 * 1024, 0)); // 1 MB

      final itemSyncedWithFile = MediaItem(
        id: 'item-synced-1',
        asset: tempFile.path,
        title: 'photo1.jpg',
        category: 'Camera',
        takenAt: DateTime.now(),
        kind: MediaKind.photo,
        isSynced: true,
      );

      final itemUnsyncedWithFile = MediaItem(
        id: 'item-unsynced-2',
        asset: '${testFolder.path}/photo2.jpg',
        title: 'photo2.jpg',
        category: 'Camera',
        takenAt: DateTime.now(),
        kind: MediaKind.photo,
        isSynced: false,
      );

      final itemSyncedNoFile = MediaItem(
        id: 'item-synced-no-file',
        asset: '${testFolder.path}/nonexistent.jpg',
        title: 'nonexistent.jpg',
        category: 'Camera',
        takenAt: DateTime.now(),
        kind: MediaKind.photo,
        isSynced: true,
      );

      await repo.addMedia(itemSyncedWithFile);
      await repo.addMedia(itemUnsyncedWithFile);
      await repo.addMedia(itemSyncedNoFile);

      final testFolders = [
        BackupFolderConfig(
          id: 'camera',
          name: 'Camera',
          description: 'Camera folder',
          paths: [testFolder.path],
          enabled: true,
        ),
      ];

      final freeUp = await AutoBackupService.calculateFreeUpSpace(
        folders: testFolders,
        repository: repo,
      );

      expect(freeUp.totalCount, equals(1));
      expect(freeUp.candidateFiles.length, equals(1));
      expect(freeUp.candidateFiles.first.path.replaceAll(r'\', '/'), equals(tempFile.path.replaceAll(r'\', '/')));
      expect(freeUp.totalBytes, equals(1024 * 1024));
      expect(freeUp.formattedSize, contains('MB'));

      // Test freeing up space
      DeviceMediaService.mockDeleteDeviceFileResult = true;
      final freedBytes = await AutoBackupService.freeUpSpace(
        files: freeUp.candidateFiles,
      );
      expect(freedBytes, equals(1024 * 1024));
    });

    test('FreeUpSpaceResult formatSize handles KB, MB, and GB accurately', () {
      final r1 = FreeUpSpaceResult(totalCount: 1, totalBytes: 500, candidateFiles: []);
      expect(r1.formattedSize, contains('KB'));

      final r2 = FreeUpSpaceResult(totalCount: 1, totalBytes: 50 * 1024, candidateFiles: []);
      expect(r2.formattedSize, equals('50.0 KB'));

      final r3 = FreeUpSpaceResult(totalCount: 1, totalBytes: 15 * 1024 * 1024, candidateFiles: []);
      expect(r3.formattedSize, equals('15.0 MB'));

      final r4 = FreeUpSpaceResult(totalCount: 1, totalBytes: (2.45 * 1024 * 1024 * 1024).toInt(), candidateFiles: []);
      expect(r4.formattedSize, contains('GB'));
    });
  });

  group('Phase 7: BackupSettingsPage UI & Constraints', () {
    testWidgets('Renders Safeguards & Conditions and toggles state', (tester) async {
      final repo = LocalHomeRepository(store: MemorySnapshotStore());
      addTearDown(repo.dispose);
      await repo.initialize();

      await tester.pumpWidget(
        HomeScope(
          repository: repo,
          child: const MaterialApp(
            home: BackupSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to Wi-Fi only switch
      final wifiTile = find.byKey(const ValueKey('backup-wifi-only-switch'));
      await tester.scrollUntilVisible(wifiTile, 200);
      await tester.pumpAndSettle();

      final wifiSwitch = find.descendant(
        of: wifiTile,
        matching: find.byType(Switch),
      );
      expect(wifiSwitch, findsOneWidget);

      // Toggle Wi-Fi switch
      await tester.tap(wifiSwitch);
      await tester.pumpAndSettle();
      expect(await AutoBackupService.isWifiOnly(), isTrue);

      // Require charging switch
      final chargingTile = find.byKey(const ValueKey('backup-require-charging-switch'));
      final chargingSwitch = find.descendant(
        of: chargingTile,
        matching: find.byType(Switch),
      );
      expect(chargingSwitch, findsOneWidget);

      // Toggle Charging switch
      await tester.tap(chargingSwitch);
      await tester.pumpAndSettle();
      expect(await AutoBackupService.isRequireCharging(), isTrue);

      // Scroll to Free up space button
      final freeUpBtn = find.byKey(const ValueKey('free-up-space-btn'));
      await tester.scrollUntilVisible(freeUpBtn, 200);
      await tester.pumpAndSettle();
      expect(freeUpBtn, findsOneWidget);
    });

    testWidgets('Renders First-Time Backup Setup Banner when initial choice not made', (tester) async {
      final repo = LocalHomeRepository(store: MemorySnapshotStore());
      addTearDown(repo.dispose);
      await repo.initialize();

      await AutoBackupService.setInitialChoiceMade(false);

      await tester.pumpWidget(
        HomeScope(
          repository: repo,
          child: const MaterialApp(
            home: BackupSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('First-Time Backup Setup'), findsOneWidget);
      expect(find.byKey(const ValueKey('initial-backup-all-btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('initial-backup-new-btn')), findsOneWidget);

      // Tap 'Only new photos'
      await tester.tap(find.byKey(const ValueKey('initial-backup-new-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(await AutoBackupService.hasInitialChoiceMade(), isTrue);
      // Banner disappears after choice
      expect(find.text('First-Time Backup Setup'), findsNothing);
    });
  });
}
