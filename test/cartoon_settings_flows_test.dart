import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/design/space_navigation.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/library_widgets.dart';
import 'package:homespace/pages/settings_pages.dart';
import 'package:homespace/pages/trash_page.dart';

class SettingsStore extends MemorySnapshotStore {
  bool failWrite = false;
  bool failRead = false;
  bool recovered = false;
  @override
  Future<StoredLibrary?> load() async {
    if (failRead) throw const SnapshotReadException();
    final result = await super.load();
    return result == null
        ? null
        : StoredLibrary(
            result.snapshot,
            recoveryNotice: recovered
                ? 'Your saved library was recovered from its backup.'
                : null,
          );
  }

  @override
  Future<void> save(LibrarySnapshot snapshot) async {
    if (failWrite) throw const FileSystemException('Disk full');
    await super.save(snapshot);
  }
}

Finder key(String value) => find.byKey(ValueKey(value));
const frame = ValueKey('settings-frame');

Future<LocalHomeRepository> start(
  WidgetTester tester, {
  SettingsStore? store,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final repository = LocalHomeRepository(
    store: store ?? SettingsStore(),
    initialAppearance: Appearance.light,
  );
  addTearDown(repository.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: frame,
      child: HomeSpaceApp(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
  if (const bool.fromEnvironment('HOMESPACE_CAPTURE')) {
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold).first);
      for (final asset
          in Directory('assets/illustrations/vector')
              .listSync()
              .whereType<File>()
              .where((asset) => asset.path.endsWith('.svg'))) {
        final loader = SvgAssetLoader(asset.path.replaceAll('\\', '/'));
        await svg.cache.putIfAbsent(
          loader.cacheKey(context),
          () => loader.loadBytes(context),
        );
      }
      for (final media in repository.media) {
        await precacheImage(AssetImage(media.asset), context);
      }
    });
    await tester.pumpAndSettle();
  }
  return repository;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  var avatarSheet = false;
  if (finder.toString().contains('avatar-') && finder.evaluate().isEmpty) {
    await tester.tap(key('profile-picture'));
    await tester.pumpAndSettle();
    avatarSheet = true;
  }
  if (finder.toString().contains('Explore sample library') &&
      finder.evaluate().isEmpty) {
    await tester.tap(key('add-photos'));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  if (avatarSheet) {
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }
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
    final file = File('output/previews/cartoon-phase-4-$name.png');
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

  testWidgets('Appearance previews locally, Back cancels and Done persists', (
    tester,
  ) async {
    final store = SettingsStore();
    final repository = await start(tester, store: store);
    await tap(tester, key('tab-profile'));
    await tap(tester, key('appearance-setting'));
    await capture(tester, 'appearance-light');
    await tap(tester, key('theme-dark'));
    expect(repository.profile.appearance, Appearance.light);
    expect(
      Theme.of(tester.element(find.text('Choose how HomeSpace looks.')))
          .brightness,
      Brightness.dark,
    );
    final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find
          .descendant(
            of: find.byType(AppearancePage),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .first,
    );
    expect(overlay.value.systemNavigationBarIconBrightness, Brightness.light);
    await capture(tester, 'appearance-dark');
    await back(tester);
    expect(repository.profile.appearance, Appearance.light);
    await tap(tester, key('appearance-setting'));
    await tap(tester, key('theme-dark'));
    await tap(tester, key('save-appearance'));
    expect(repository.profile.appearance, Appearance.dark);
    final restored = LocalHomeRepository(store: store);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.profile.appearance, Appearance.dark);
  });

  testWidgets(
    'System appearance follows platform changes without an early save',
    (tester) async {
      final repository = await start(tester);
      await tap(tester, key('tab-profile'));
      await tap(tester, key('appearance-setting'));
      await tap(tester, key('theme-system'));
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Choose how HomeSpace looks.')))
            .brightness,
        Brightness.dark,
      );
      expect(repository.profile.appearance, Appearance.light);
      await tap(tester, key('save-appearance'));
      expect(repository.profile.appearance, Appearance.system);
    },
  );

  testWidgets(
    'Profile drafts cancel and failed saves retain name and avatar for retry',
    (tester) async {
      final store = SettingsStore();
      final repository = await start(tester, store: store);
      await tap(tester, key('tab-profile'));
      await tap(tester, key('edit-profile'));
      await capture(tester, 'edit-profile');
      await tester.enterText(key('profile-name'), 'Anika');
      await tap(tester, key('avatar-blue'));
      await back(tester);
      expect(repository.profile.name, 'Maya');
      expect(repository.profile.avatarTone, AvatarTone.orange);
      await tap(tester, key('edit-profile'));
      await tester.enterText(key('profile-name'), 'Anika');
      await tap(tester, key('avatar-blue'));
      store.failWrite = true;
      await tap(tester, key('save-profile'));
      expect(find.text('Couldn’t save that change'), findsOneWidget);
      expect(repository.profile.name, 'Maya');
      await tap(tester, find.text('OK'));
      expect(
        tester.widget<TextFormField>(key('profile-name')).controller!.text,
        'Anika',
      );
      store.failWrite = false;
      await tap(tester, key('save-profile'));
      expect(repository.profile.name, 'Anika');
      expect(repository.profile.avatarTone, AvatarTone.blue);
    },
  );

  testWidgets(
    'Trash restores selected records and destructive cancellation keeps the rest',
    (tester) async {
      final repository = await start(tester);
      await repository.moveManyToTrash(['media-01', 'media-02', 'media-03']);
      await tester.pumpAndSettle();
      await tap(tester, key('tab-profile'));
      await tap(tester, key('trash-setting'));
      await tester.longPress(key('trash-media-01'));
      await tester.pumpAndSettle();
      await tap(tester, key('trash-media-02'));
      await capture(tester, 'trash-light');
      await tap(tester, key('delete-selected'));
      await capture(tester, 'delete-confirmation');
      await back(tester);
      expect(repository.trash, hasLength(3));
      await tap(tester, key('restore-selected'));
      expect(repository.trash.map((entry) => entry.mediaId), ['media-03']);
      expect(repository.favorites.contains('media-01'), isTrue);
      expect(repository.albums.first.mediaIds.contains('media-01'), isTrue);
      await repository.setAppearance(Appearance.dark);
      await tester.pumpAndSettle();
      await capture(tester, 'trash-dark');
      await tap(tester, key('empty-trash'));
      await tap(tester, key('confirm-action'));
      expect(find.text('Nothing left behind'), findsOneWidget);
      expect(repository.mediaById('media-03'), isNull);
      await capture(tester, 'trash-empty');
    },
  );

  testWidgets(
    'Recovery and offline banners are visible and demo retries preserve stored data',
    (tester) async {
      final store = SettingsStore();
      final seed = LocalHomeRepository(store: store);
      await seed.initialize();
      seed.dispose();
      store.recovered = true;
      final repository = await start(tester, store: store);
      final saved = store.contents;
      expect(
        find.text('Your saved library was recovered from its backup.'),
        findsOneWidget,
      );
      await capture(tester, 'recovered-library');
      repository.setScenario(DemoScenario.empty);
      await tester.pumpAndSettle();
      await capture(tester, 'empty-library');
      await tap(tester, find.text('Explore sample library'));
      expect(repository.media, hasLength(12));
      repository.setScenario(DemoScenario.failed);
      await tester.pumpAndSettle();
      await capture(tester, 'failed-preview');
      await tap(tester, find.text('Try again'));
      expect(store.contents, saved);
      store.recovered = false;
      final clean = await start(tester, store: store);
      clean.setScenario(DemoScenario.offline);
      await tester.pumpAndSettle();
      expect(
        find.text('Offline demo · Showing saved local memories'),
        findsOneWidget,
      );
      await capture(tester, 'offline-library');
      await tap(tester, find.text('Retry'));
      expect(clean.media, hasLength(12));
      store.failRead = true;
      await start(tester, store: store);
      expect(find.text('Retry opening library'), findsOneWidget);
      await capture(tester, 'recovery-error');
      store.failRead = false;
      await tap(tester, find.text('Retry opening library'));
      expect(store.contents, saved);
    },
  );

  testWidgets(
    'Settings trash dialogs and loading/error states fit large text and keyboard insets',
    (tester) async {
      final repository = await start(tester);
      await repository.moveToTrash('media-01');
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final size in [const Size(320, 700), const Size(740, 360)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        var context = tester.element(find.byType(SpaceNavigation));
        openSpacePage<void>(context, const EditProfilePage());
        await tester.pumpAndSettle();
        if (size.width < 400) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          await tester.ensureVisible(key('save-profile'));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(key('save-profile')).bottom,
            lessThanOrEqualTo(size.height - 280),
          );
          tester.view.resetViewInsets();
        }
        expect(tester.takeException(), isNull);
        await back(tester);
        context = tester.element(find.byType(SpaceNavigation));
        openSpacePage<void>(context, const AppearancePage());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await back(tester);
        context = tester.element(find.byType(SpaceNavigation));
        openSpacePage<void>(context, const TrashPage());
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          key('empty-trash'),
          100,
          scrollable: find
              .descendant(
                of: key('trash-scroll'),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tap(tester, key('empty-trash'));
        expect(tester.takeException(), isNull);
        await back(tester);
        await back(tester);
        repository.setScenario(DemoScenario.loading);
        await tester.pump();
        expect(tester.takeException(), isNull);
        repository.setScenario(DemoScenario.failed);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        repository.setScenario(DemoScenario.populated);
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'Settings and destructive controls have readable labels contrast and touch targets',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final repository = await start(tester);
        Future<void> check() async {
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }

        await tap(tester, key('tab-profile'));
        await tap(tester, key('edit-profile'));
        await check();
        await back(tester);
        await tap(tester, key('appearance-setting'));
        await check();
        await back(tester);
        await repository.moveToTrash('media-01');
        await tester.pumpAndSettle();
        await tap(tester, key('trash-setting'));
        await tester.longPress(key('trash-media-01'));
        await tester.pumpAndSettle();
        await check();
        await tap(tester, key('delete-selected'));
        await check();
      } finally {
        handle.dispose();
      }
    },
  );
}
