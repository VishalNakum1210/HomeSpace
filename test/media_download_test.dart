import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/application/device_media_service.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/media_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PaintingBinding.instance.imageCache.maximumSize = 2500;
  });

  testWidgets(
    'MediaViewer renders Download button in top app bar and bottom action bar, and downloads media',
    (tester) async {
      DeviceMediaService.debugOverrideIsAndroid = true;
      addTearDown(() => DeviceMediaService.debugOverrideIsAndroid = false);

      final log = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.homespace.homespace/media_saver'),
        (call) async {
          log.add(call);
          if (call.method == 'saveMedia') {
            return '/storage/emulated/0/Pictures/HomeSpace/mock.jpg';
          }
          return null;
        },
      );

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = LocalHomeRepository(
        store: MemorySnapshotStore(),
        initialAppearance: Appearance.light,
      );
      addTearDown(repository.dispose);

      await tester.pumpWidget(HomeSpaceApp(repository: repository));
      await tester.pumpAndSettle();

      // Tap on first memory to open MediaViewer
      await tester.tap(find.byKey(const ValueKey('memory-media-01')));
      await tester.pumpAndSettle();

      expect(find.byType(MediaViewer), findsOneWidget);

      // Verify Download button in top bar exists
      final topDownloadFinder = find.byKey(const ValueKey('viewer-download'));
      expect(topDownloadFinder, findsOneWidget);

      // Verify Download button in bottom bar exists
      final bottomDownloadFinder = find.byKey(const ValueKey('download-memory'));
      expect(bottomDownloadFinder, findsOneWidget);

      // Tap the download button
      await tester.runAsync(() async {
        await tester.tap(topDownloadFinder);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      // Verify channel was invoked with saveMedia
      expect(log.any((call) => call.method == 'saveMedia'), isTrue);

      // Verify success snackbar appears
      expect(find.textContaining('Saved to device gallery'), findsOneWidget);
    },
  );

  testWidgets(
    'MediaViewer displays floating download progress card while downloading',
    (tester) async {
      DeviceMediaService.debugOverrideIsAndroid = true;
      addTearDown(() => DeviceMediaService.debugOverrideIsAndroid = false);

      final saveCompleter = Completer<String>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.homespace.homespace/media_saver'),
        (call) async {
          if (call.method == 'saveMedia') {
            return await saveCompleter.future;
          }
          return null;
        },
      );

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = LocalHomeRepository(
        store: MemorySnapshotStore(),
        initialAppearance: Appearance.light,
      );
      addTearDown(repository.dispose);

      await tester.pumpWidget(HomeSpaceApp(repository: repository));
      await tester.pumpAndSettle();

      // Open media viewer
      await tester.tap(find.byKey(const ValueKey('memory-media-01')));
      await tester.pumpAndSettle();

      // Tap download in bottom action bar
      final bottomDownload = find.byKey(const ValueKey('download-memory'));
      await tester.runAsync(() async {
        await tester.tap(bottomDownload);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      // While saving to device, verify progress card and progress bar are rendered
      expect(find.byKey(const ValueKey('viewer-download-progress-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer-download-progress-bar')), findsOneWidget);

      // Verify bottom action shows "Downloading…"
      expect(find.text('Downloading…'), findsWidgets);

      // Complete the save operation
      await tester.runAsync(() async {
        saveCompleter.complete('/storage/emulated/0/Pictures/HomeSpace/sample1.jpg');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Progress card dismissed and success snackbar visible
      expect(find.byKey(const ValueKey('viewer-download-progress-card')), findsNothing);
      expect(find.textContaining('Saved to device gallery'), findsOneWidget);
    },
  );

  testWidgets(
    'Exiting MediaViewer while downloading retains progress in GlobalDownloadBanner',
    (tester) async {
      DeviceMediaService.debugOverrideIsAndroid = true;
      addTearDown(() => DeviceMediaService.debugOverrideIsAndroid = false);

      final saveCompleter = Completer<String>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.homespace.homespace/media_saver'),
        (call) async {
          if (call.method == 'saveMedia') {
            return await saveCompleter.future;
          }
          return null;
        },
      );

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = LocalHomeRepository(
        store: MemorySnapshotStore(),
        initialAppearance: Appearance.light,
      );
      addTearDown(repository.dispose);

      await tester.pumpWidget(HomeSpaceApp(repository: repository));
      await tester.pumpAndSettle();

      // Open media viewer
      await tester.tap(find.byKey(const ValueKey('memory-media-01')));
      await tester.pumpAndSettle();

      // Start download
      final bottomDownload = find.byKey(const ValueKey('download-memory'));
      await tester.runAsync(() async {
        await tester.tap(bottomDownload);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      // Pop MediaViewer back to PhotosPage
      await tester.tap(find.byTooltip('Close viewer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Verify MediaViewer is gone
      expect(find.byType(MediaViewer), findsNothing);

      // Verify GlobalDownloadBanner is visible with progress bar
      expect(find.byKey(const ValueKey('global-download-banner')), findsOneWidget);

      // Complete the save operation
      await tester.runAsync(() async {
        saveCompleter.complete('/storage/emulated/0/Pictures/HomeSpace/sample1.jpg');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Banner shows completion state
      expect(find.textContaining('Saved to device gallery'), findsWidgets);
    },
  );

  group('DeviceMediaService & AutoBackupService', () {
    test('saveMediaToDevice invokes media_saver channel on Android', () async {
      DeviceMediaService.debugOverrideIsAndroid = true;
      addTearDown(() => DeviceMediaService.debugOverrideIsAndroid = false);

      String? passedFile;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.homespace.homespace/media_saver'),
        (call) async {
          if (call.method == 'saveMedia') {
            passedFile = call.arguments['fileName'] as String?;
            return 'content://media/external/images/123';
          }
          return null;
        },
      );

      final result = await DeviceMediaService.saveMediaToDevice(
        bytes: [1, 2, 3],
        fileName: 'my_download.jpg',
        mimeType: 'image/jpeg',
      );

      expect(result, 'content://media/external/images/123');
      expect(passedFile, 'my_download.jpg');
    });

    test('saveMediaToDevice with filePath invokes media_saver channel without allocating bytes', () async {
      DeviceMediaService.debugOverrideIsAndroid = true;
      addTearDown(() => DeviceMediaService.debugOverrideIsAndroid = false);

      String? passedPath;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.homespace.homespace/media_saver'),
        (call) async {
          if (call.method == 'saveMedia') {
            passedPath = call.arguments['filePath'] as String?;
            return 'content://media/external/video/456';
          }
          return null;
        },
      );

      final result = await DeviceMediaService.saveMediaToDevice(
        filePath: '/tmp/test_video.mp4',
        fileName: 'test_video.mp4',
        mimeType: 'video/mp4',
      );

      expect(result, 'content://media/external/video/456');
      expect(passedPath, '/tmp/test_video.mp4');
    });

    test('permission and queryCameraMedia channels succeed on Android', () async {
      DeviceMediaService.debugOverrideIsAndroid = true;
      addTearDown(() => DeviceMediaService.debugOverrideIsAndroid = false);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.homespace.homespace/permissions'),
        (call) async {
          if (call.method == 'checkStoragePermission') return true;
          if (call.method == 'requestStoragePermission') return true;
          if (call.method == 'queryCameraMedia') {
            return [
              {
                'path': '/storage/emulated/0/DCIM/Camera/IMG_01.jpg',
                'name': 'IMG_01.jpg',
                'size': 1024,
                'mimeType': 'image/jpeg',
                'isVideo': false,
              }
            ];
          }
          return null;
        },
      );

      expect(await DeviceMediaService.checkStoragePermission(), isTrue);
      expect(await DeviceMediaService.requestStoragePermission(), isTrue);

      final media = await DeviceMediaService.queryCameraMedia();
      expect(media.length, 1);
      expect(media.first['name'], 'IMG_01.jpg');
    });
  });
}
