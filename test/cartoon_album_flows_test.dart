import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/album_editor_page.dart';
import 'package:homespace/pages/album_members_page.dart';
import 'package:homespace/pages/album_page.dart';
import 'package:homespace/pages/library_widgets.dart';
import 'package:homespace/design/space_navigation.dart';

class AlbumFlowStore extends MemorySnapshotStore {
  bool fail = false;
  @override
  Future<void> save(LibrarySnapshot snapshot) async {
    if (fail) throw const FileSystemException('Disk full');
    await super.save(snapshot);
  }
}

Finder key(String value) => find.byKey(ValueKey(value));
const frame = ValueKey('album-flow-frame');

Future<LocalHomeRepository> start(
  WidgetTester tester, {
  AlbumFlowStore? store,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final repository = LocalHomeRepository(
    store: store ?? AlbumFlowStore(),
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
    final context = tester.element(find.text('Your happy place'));
    await tester.runAsync(() async {
      for (final media in repository.media) {
        await precacheImage(AssetImage(media.asset), context);
      }
    });
    await tester.pumpAndSettle();
  }
  return repository;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> openFamilyAlbum(WidgetTester tester) async {
  await tap(tester, key('tab-collections'));
  await tap(tester, key('album-album-family'));
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
    final file = File('output/previews/cartoon-phase-3-$name.png');
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

  testWidgets('New album cover is a draft until Save and survives recreation', (
    tester,
  ) async {
    final store = AlbumFlowStore();
    final repository = await start(tester, store: store);
    await tap(tester, key('tab-collections'));
    await tap(tester, key('new-album'));
    expect(find.byType(AlbumEditorPage), findsOneWidget);
    expect(find.byType(SpaceNavigation), findsNothing);
    await tester.enterText(key('album-name'), 'Mountain mornings');
    await tester.enterText(key('album-description'), 'The places we love.');
    await tap(tester, key('choose-album-cover'));
    await tap(tester, key('cover-media-03'));
    await tap(tester, key('use-album-cover'));
    expect(repository.albums, hasLength(4));
    await capture(tester, 'create-album');
    await tap(tester, key('save-album-editor'));
    expect(repository.albums, hasLength(5));
    final created = repository.albums.last;
    expect(created.coverId, 'media-03');
    expect(created.mediaIds, ['media-03']);
    final restored = LocalHomeRepository(store: store);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.albums.last.title, 'Mountain mornings');
    expect(restored.albums.last.coverId, 'media-03');
  });

  testWidgets(
    'Failed edit keeps draft cover and fields and retry saves them together',
    (tester) async {
      final store = AlbumFlowStore();
      final repository = await start(tester, store: store);
      await openFamilyAlbum(tester);
      await capture(tester, 'album-light');
      await tap(tester, find.byTooltip('Album options'));
      await tap(tester, find.text('Edit album'));
      await tester.enterText(key('album-name'), 'Our people');
      await tester.enterText(key('album-description'), 'Summer together');
      await tap(tester, key('choose-album-cover'));
      expect(key('cover-media-03'), findsNothing);
      await tap(tester, key('cover-media-04'));
      await tap(tester, key('use-album-cover'));
      await capture(tester, 'edit-album');
      final before = repository.snapshot;
      store.fail = true;
      await tap(tester, key('save-album-editor'));
      expect(find.text('Couldn’t save that change'), findsOneWidget);
      expect(repository.snapshot, same(before));
      await tap(tester, find.text('OK'));
      expect(
        tester.widget<TextFormField>(key('album-name')).controller!.text,
        'Our people',
      );
      store.fail = false;
      await tap(tester, key('save-album-editor'));
      final result = repository.albums.first;
      expect(result.title, 'Our people');
      expect(result.description, 'Summer together');
      expect(result.coverId, 'media-04');
    },
  );

  testWidgets(
    'Editing a title preserves a trashed cover for later restoration',
    (tester) async {
      final repository = await start(tester);
      await repository.moveToTrash('media-01');
      await tester.pumpAndSettle();
      await openFamilyAlbum(tester);
      await tap(tester, find.byTooltip('Album options'));
      await tap(tester, find.text('Edit album'));
      await tester.enterText(key('album-name'), 'Still our people');
      await tap(tester, key('save-album-editor'));
      expect(repository.albums.first.coverId, 'media-01');
      await repository.restore('media-01');
      expect(repository.coverFor(repository.albums.first)?.id, 'media-01');
    },
  );

  testWidgets(
    'Picker keeps selections across search and Favorites and adds them once',
    (tester) async {
      final repository = await start(tester);
      await openFamilyAlbum(tester);
      await tap(tester, key('add-album-photos'));
      expect(key('pick-media-01'), findsNothing);
      await tap(tester, key('pick-media-02'));
      await tap(tester, find.text('Favorites'));
      await tester.enterText(key('album-photo-search'), 'stars');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tap(tester, key('pick-media-06'));
      await tester.enterText(key('album-photo-search'), '');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tap(tester, find.text('All').first);
      await capture(tester, 'add-photos');
      await tap(tester, key('save-album-photos'));
      final album = repository.albums.first;
      expect(album.mediaIds, hasLength(6));
      expect(
        album.mediaIds.toSet().containsAll(['media-02', 'media-06']),
        isTrue,
      );
      expect(album.addedBy['media-06'], repository.profile.userId);
    },
  );

  testWidgets(
    'Permission draft does not change a role until Save and failed saves can retry',
    (tester) async {
      final store = AlbumFlowStore();
      final repository = await start(tester, store: store);
      await openFamilyAlbum(tester);
      await tap(tester, key('album-members'));
      expect(find.byType(AlbumMembersPage), findsOneWidget);
      expect(key('member-options-member-maya'), findsNothing);
      await capture(tester, 'members-light');
      await tap(tester, key('member-options-member-sam'));
      expect(key('permission-owner'), findsNothing);
      await tap(tester, key('permission-contributor'));
      expect(repository.albums.first.roleFor('member-sam'), AlbumRole.viewer);
      await capture(tester, 'permissions');
      store.fail = true;
      await tap(tester, key('save-member-permissions'));
      expect(find.text('Couldn’t save that change'), findsOneWidget);
      expect(repository.albums.first.roleFor('member-sam'), AlbumRole.viewer);
      await tap(tester, find.text('OK'));
      store.fail = false;
      await tap(tester, key('save-member-permissions'));
      expect(
        repository.albums.first.roleFor('member-sam'),
        AlbumRole.contributor,
      );
      expect(repository.albums[1].roleFor('member-sam'), isNull);
      await repository.setAppearance(Appearance.dark);
      await tester.pumpAndSettle();
      await capture(tester, 'members-dark');
      await back(tester);
      await capture(tester, 'album-dark');
    },
  );

  testWidgets(
    'Editor cover picker members and permissions fit large text and landscape',
    (tester) async {
      final repository = await start(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final size in [const Size(320, 700), const Size(740, 360)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        var context = tester.element(find.byType(SpaceNavigation));
        openAlbumEditor(context, album: repository.albums.first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Editor at $size');
        if (size.width < 400) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Editor with keyboard',
          );
          expect(
            tester.getRect(key('save-album-editor')).bottom,
            lessThanOrEqualTo(size.height - 280),
          );
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
        }
        await tap(tester, key('choose-album-cover'));
        expect(tester.takeException(), isNull, reason: 'Cover picker at $size');
        await back(tester);
        await back(tester);
        context = tester.element(find.byType(SpaceNavigation));
        openSpacePage<void>(
          context,
          const AlbumMembersPage(albumId: 'album-family'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Members at $size');
        await tester.scrollUntilVisible(
          key('member-options-member-sam'),
          100,
          scrollable: find
              .descendant(
                of: find.byType(AlbumMembersPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tap(tester, key('member-options-member-sam'));
        expect(tester.takeException(), isNull, reason: 'Permissions at $size');
        await back(tester);
        await back(tester);
        context = tester.element(find.byType(SpaceNavigation));
        openSpacePage<void>(
          context,
          const AlbumMediaPicker(albumId: 'album-family'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Photo picker at $size');
        await back(tester);
      }
    },
  );

  testWidgets(
    'New album controls have labeled touch targets and readable contrast',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await start(tester);
        await tap(tester, key('tab-collections'));
        await tap(tester, key('new-album'));
        Future<void> check() async {
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }

        await check();
        await back(tester);
        await tap(tester, key('album-album-family'));
        await tap(tester, key('album-members'));
        await check();
        await tap(tester, key('member-options-member-sam'));
        await check();
      } finally {
        handle.dispose();
      }
    },
  );
}
