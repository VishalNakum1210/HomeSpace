import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/demo_remote_repositories.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/design/space_navigation.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/connection_page.dart';
import 'package:homespace/pages/library_widgets.dart';
import 'package:homespace/pages/uploads_page.dart';

Finder key(String value) => find.byKey(ValueKey(value));
const frame = ValueKey('remote-frame');

class SlowHome extends LocalHomeRepository {
  final delayed = DemoConnectionRepository(delay: const Duration(seconds: 2));
  SlowHome() : super(store: MemorySnapshotStore());
  @override
  DemoConnectionRepository get connection => delayed;
  @override
  void dispose() {
    delayed.dispose();
    super.dispose();
  }
}

Future<LocalHomeRepository> start(
  WidgetTester tester, {
  LocalHomeRepository? repository,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final repo =
      repository ??
      LocalHomeRepository(
        store: MemorySnapshotStore(),
        initialAppearance: Appearance.light,
      );
  addTearDown(repo.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: frame,
      child: HomeSpaceApp(repository: repo),
    ),
  );
  await tester.pumpAndSettle();
  if (const bool.fromEnvironment('HOMESPACE_CAPTURE')) {
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold).first);
      for (final media in repo.media) {
        await precacheImage(AssetImage(media.asset), context);
      }
    });
  }
  return repo;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty &&
      (finder.toString().contains('server-setting') ||
          finder.toString().contains('uploads-setting'))) {
    await tester.ensureVisible(key('about-setting'));
    await tester.tap(key('about-setting'));
    await tester.pumpAndSettle();
  }
  final page = find.byType(BottomSheet).evaluate().isNotEmpty
      ? find.byType(BottomSheet)
      : find.byType(UploadsPage).evaluate().isNotEmpty
      ? find.byType(UploadsPage)
      : find.byType(ConnectionPage).evaluate().isNotEmpty
      ? find.byType(ConnectionPage)
      : find.byKey(const PageStorageKey('profile-scroll'));
  final scroll = find
      .descendant(of: page, matching: find.byType(Scrollable))
      .first;
  if (scroll.evaluate().isNotEmpty) {
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 180, scrollable: scroll);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester, Widget page) async {
  openSpacePage<void>(tester.element(find.byType(SpaceNavigation)), page);
  await tester.pumpAndSettle();
}

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('HOMESPACE_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(frame),
  );
  void repaint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  repaint(boundary);
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('output/previews/frontend-phase-5-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'Profile navigation, address validation and session connection update together',
    (tester) async {
      final repo = await start(tester);
      final saved = (repo.store as MemorySnapshotStore).contents;
      await tester.tap(key('tab-profile'));
      await tester.pumpAndSettle();
      await tap(tester, key('server-setting'));
      await capture(tester, 'server-disconnected');
      await tap(tester, key('connect-server'));
      expect(find.textContaining('Enter an HTTP'), findsOneWidget);
      for (final address in [
        'file:///photos',
        'https://user:secret@home.test',
        'https://home.test?token=secret',
      ]) {
        await tester.enterText(key('server-address'), address);
        await tap(tester, key('connect-server'));
        expect(repo.connection.status.phase, ConnectionPhase.disconnected);
      }
      await tester.enterText(key('server-address'), 'http://192.168.1.20:8080');
      await tap(tester, key('connect-server'));
      expect(find.text('Demo connected'), findsOneWidget);
      expect(repo.connection.status.address!.port, 8080);
      await capture(tester, 'server-connected');
      await back(tester);
      await tester.ensureVisible(key('about-setting'));
      await tester.tap(key('about-setting'));
      await tester.pumpAndSettle();
      expect(find.text('Demo connected'), findsOneWidget);
      await tap(tester, key('server-setting'));
      await repo.setAppearance(Appearance.dark);
      await tester.pumpAndSettle();
      await capture(tester, 'server-dark');
      await repo.setAppearance(Appearance.light);
      await tester.pumpAndSettle();
      await tap(tester, key('connection-uploads'));
      expect(find.text('Upload queue'), findsOneWidget);
      await back(tester);
      await tap(tester, key('connect-server'));
      expect(repo.connection.status.phase, ConnectionPhase.disconnected);
      expect(
        tester.widget<TextFormField>(key('server-address')).controller!.text,
        contains('192.168.1.20'),
      );
      await back(tester);
      await tap(tester, key('uploads-setting'));
      expect(find.text('2 of 5 sample items completed'), findsOneWidget);
      expect((repo.store as MemorySnapshotStore).contents, saved);
    },
  );

  testWidgets(
    'Connection offline and failure retry recover without resetting the library',
    (tester) async {
      final repo = await start(tester);
      final connection = repo.connection as DemoConnectionRepository;
      final saved = (repo.store as MemorySnapshotStore).contents;
      await open(tester, const ConnectionPage());
      await tester.enterText(key('server-address'), 'https://home.test/family');
      connection.scenario = DemoScenario.offline;
      await tap(tester, key('connect-server'));
      expect(find.text('Offline preview'), findsOneWidget);
      await capture(tester, 'server-offline');
      connection.scenario = DemoScenario.failed;
      await tap(tester, key('connect-server'));
      expect(find.text("Let's try again"), findsOneWidget);
      await capture(tester, 'server-failed');
      connection.scenario = DemoScenario.populated;
      await tap(tester, key('connect-server'));
      expect(find.text('Demo connected'), findsOneWidget);
      expect((repo.store as MemorySnapshotStore).contents, saved);
    },
  );

  testWidgets('Canceling a pending connection ignores its late completion', (
    tester,
  ) async {
    final repo = SlowHome();
    await start(tester, repository: repo);
    await open(tester, const ConnectionPage());
    await tester.enterText(key('server-address'), 'http://home.test');
    await tester.ensureVisible(key('connect-server'));
    await tester.tap(key('connect-server'));
    await tester.pump();
    expect(find.text('Cancel preview'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(key('server-address')).enabled,
      isFalse,
    );
    await capture(tester, 'server-connecting');
    await tester.tap(key('connect-server'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(repo.connection.status.phase, ConnectionPhase.disconnected);
    expect(find.text('Ready to explore'), findsOneWidget);
  });

  testWidgets(
    'Queue actions filter immediately and cancellation preserves saved photos',
    (tester) async {
      final repo = await start(tester);
      final saved = (repo.store as MemorySnapshotStore).contents;
      await open(tester, const UploadsPage());
      await capture(tester, 'queue-light');
      await tap(tester, key('queue-active'));
      await tap(tester, key('upload-action-upload-3'));
      expect(repo.uploads.items[2].phase, UploadPhase.paused);
      await tap(tester, key('upload-action-upload-3'));
      expect(repo.uploads.items[2].phase, UploadPhase.queued);
      await tap(tester, key('upload-action-upload-5'));
      expect(repo.uploads.items[4].phase, UploadPhase.queued);
      expect(repo.uploads.items[4].bytesSent, 0);
      await tap(tester, key('upload-cancel-upload-3'));
      await capture(tester, 'queue-cancel');
      await back(tester);
      expect(repo.uploads.items[2].phase, UploadPhase.queued);
      await tap(tester, key('upload-cancel-upload-3'));
      await tester.tap(key('confirm-action'));
      await tester.pumpAndSettle();
      expect(repo.uploads.items[2].phase, UploadPhase.canceled);
      expect(key('upload-state-upload-3'), findsNothing);
      await tap(tester, key('queue-finished'));
      expect(find.text('Canceled'), findsOneWidget);
      expect(find.text('2 of 5 sample items completed'), findsOneWidget);
      await capture(tester, 'queue-finished');
      expect((repo.store as MemorySnapshotStore).contents, saved);
      expect(repo.mediaById('media-03'), isNotNull);
    },
  );

  testWidgets(
    'Queue batch actions, missing media, dark mode and empty state remain consistent',
    (tester) async {
      final repo = await start(tester);
      await repo.moveToTrash('media-03');
      await repo.deletePermanently('media-03');
      await open(tester, const UploadsPage());
      await tap(tester, key('queue-active'));
      expect(find.text('Unavailable memory'), findsOneWidget);
      await tap(tester, key('pause-all'));
      expect(
        repo.uploads.items
            .where((item) => item.phase == UploadPhase.paused)
            .length,
        2,
      );
      await tap(tester, key('resume-all'));
      await tap(tester, key('retry-failed'));
      expect(
        repo.uploads.items
            .where((item) => item.phase == UploadPhase.queued)
            .length,
        3,
      );
      await repo.setAppearance(Appearance.dark);
      await tester.pumpAndSettle();
      await capture(tester, 'queue-dark');
      for (final item in repo.uploads.items.where(activeUpload)) {
        repo.uploads.cancel(item.id);
      }
      await tester.pumpAndSettle();
      expect(find.text('All quiet here'), findsOneWidget);
      repo.setScenario(DemoScenario.empty);
      await tester.pumpAndSettle();
      expect(find.text('Room for new memories'), findsOneWidget);
      await capture(tester, 'queue-empty');
    },
  );

  testWidgets(
    'Connection and queue fit narrow landscape large text and keyboard',
    (tester) async {
      final repo = await start(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final size in [const Size(320, 700), const Size(740, 360)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        await open(tester, const ConnectionPage());
        tester.view.viewInsets = const FakeViewPadding(bottom: 200);
        await tester.pumpAndSettle();
        await tester.enterText(key('server-address'), 'http://home.test');
        await tap(tester, key('connect-server'));
        expect(tester.takeException(), isNull);
        repo.connection.disconnect();
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();
        await back(tester);
        await open(tester, const UploadsPage());
        await tap(tester, key('queue-active'));
        await tap(tester, key('upload-cancel-upload-3'));
        expect(tester.takeException(), isNull);
        await back(tester);
        await back(tester);
      }
    },
  );

  testWidgets(
    'Connection queue and cancellation meet Android accessibility guidelines',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await start(tester);
        Future<void> check() async {
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }

        await open(tester, const ConnectionPage());
        await tester.ensureVisible(key('connect-server'));
        await tester.pumpAndSettle();
        await check();
        await back(tester);
        await open(tester, const UploadsPage());
        await check();
        await tap(tester, key('queue-active'));
        await tap(tester, key('upload-cancel-upload-3'));
        await check();
      } finally {
        handle.dispose();
      }
    },
  );
}
