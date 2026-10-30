import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/design/space_navigation.dart';
import 'package:homespace/domain/models.dart';

class TestFailureStore extends MemorySnapshotStore {
  bool failRead = false;
  bool failWrite = false;
  @override
  Future<StoredLibrary?> load() async {
    if (failRead) throw const SnapshotReadException();
    return super.load();
  }

  @override
  Future<void> save(LibrarySnapshot snapshot) async {
    if (failWrite) throw const FileSystemException('Simulated full disk');
    return super.save(snapshot);
  }
}

Future<void> render(WidgetTester tester, LocalHomeRepository repository) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(HomeSpaceApp(repository: repository));
  await tester.pumpAndSettle();
}

Future<void> tab(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey('tab-$name')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf'))).load();
  });

  testWidgets(
    'UI saves a new album, favorite, profile and theme and restores them after app recreation',
    (tester) async {
      final store = MemorySnapshotStore();
      final repository = LocalHomeRepository(
        store: store,
        initialAppearance: Appearance.light,
      );
      addTearDown(repository.dispose);
      await render(tester, repository);

      await tab(tester, 'collections');
      await tester.tap(find.byKey(const ValueKey('new-album')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-album-editor')));
      await tester.pumpAndSettle();
      expect(find.text('Give your album a name.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('album-name')),
        'Beach days',
      );
      await tester.tap(find.byKey(const ValueKey('save-album-editor')));
      await tester.pumpAndSettle();
      final albumId = repository.albums.last.id;

      await tab(tester, 'photos');
      await tester.tap(find.byKey(const ValueKey('memory-media-01')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-favorite')));
      await tester.pumpAndSettle();
      expect(repository.favorites.contains('media-01'), isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('choose-album')));
      await tester.tap(find.byKey(const ValueKey('choose-album')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ValueKey('add-to-$albumId')));
      await tester.tap(find.byKey(ValueKey('add-to-$albumId')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tab(tester, 'profile');
      await tester.tap(find.byKey(const ValueKey('edit-profile')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Anika',
      );
      await tester.tap(find.byKey(const ValueKey('profile-picture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('avatar-blue')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-profile')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('appearance-setting')),
      );
      await tester.tap(find.byKey(const ValueKey('appearance-setting')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-appearance')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      final restored = LocalHomeRepository(store: store);
      addTearDown(restored.dispose);
      await render(tester, restored);
      expect(restored.profile.name, 'Anika');
      expect(restored.profile.avatarTone, AvatarTone.blue);
      expect(restored.profile.appearance, Appearance.dark);
      expect(restored.favorites.contains('media-01'), isFalse);
      expect(
        restored.albums.singleWhere((album) => album.id == albumId).mediaIds,
        ['media-01'],
      );
      expect(
        Theme.of(tester.element(find.byType(SpaceNavigation))).brightness,
        Brightness.dark,
      );
      await tab(tester, 'profile');
      expect(find.text('Hi, Anika!'), findsOneWidget);
      await tab(tester, 'collections');
      await tester.ensureVisible(find.text('Beach days'));
      expect(find.text('Beach days'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Read failure shows a recoverable boot screen; retry opens the same library',
    (tester) async {
      final store = TestFailureStore()..failRead = true;
      final repository = LocalHomeRepository(store: store);
      addTearDown(repository.dispose);
      await render(tester, repository);
      expect(find.text('Retry opening library'), findsOneWidget);
      expect(find.byType(SpaceNavigation), findsNothing);
      store.failRead = false;
      await tester.tap(find.text('Retry opening library'));
      await tester.pumpAndSettle();
      expect(find.byType(SpaceNavigation), findsOneWidget);
      expect(repository.media.length, 12);
    },
  );

  testWidgets(
    'Failed appearance save stays visible above the sheet and keeps the prior theme',
    (tester) async {
      final store = TestFailureStore();
      final repository = LocalHomeRepository(
        store: store,
        initialAppearance: Appearance.light,
      );
      addTearDown(repository.dispose);
      await render(tester, repository);
      await tab(tester, 'profile');
      await tester.tap(find.byKey(const ValueKey('appearance-setting')));
      await tester.pumpAndSettle();
      store.failWrite = true;
      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-appearance')));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t save that change'), findsOneWidget);
      expect(repository.profile.appearance, Appearance.light);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      store.failWrite = false;
      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-appearance')));
      await tester.pumpAndSettle();
      expect(repository.profile.appearance, Appearance.dark);
    },
  );

  testWidgets(
    'Empty, loading, offline and failure previews never erase the stored library',
    (tester) async {
      final store = MemorySnapshotStore();
      final repository = LocalHomeRepository(store: store);
      addTearDown(repository.dispose);
      await render(tester, repository);
      final saved = store.contents;
      repository.setScenario(DemoScenario.empty);
      await tester.pumpAndSettle();
      expect(find.text('Your memories start here'), findsOneWidget);
      await tab(tester, 'collections');
      expect(find.text('Stories start here'), findsOneWidget);
      repository.setScenario(DemoScenario.loading);
      await tester.pump();
      expect(find.text('Loading demo memories…'), findsOneWidget);
      repository.setScenario(DemoScenario.failed);
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load this preview'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(repository.albums.length, 4);
      await tab(tester, 'photos');
      repository.setScenario(DemoScenario.offline);
      await tester.pumpAndSettle();
      expect(
        find.text('Offline demo · Showing saved local memories'),
        findsOneWidget,
      );
      expect(store.contents, saved);
      expect(tester.takeException(), isNull);
    },
  );
}
