import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/design/space_navigation.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/album_page.dart';
import 'package:homespace/pages/library_widgets.dart';
import 'package:homespace/pages/media_viewer.dart';
import 'package:homespace/pages/trash_page.dart';

class FlowStore extends MemorySnapshotStore {
  bool fail = false;
  @override
  Future<void> save(LibrarySnapshot snapshot) async {
    if (fail) throw const FileSystemException('Disk full');
    return super.save(snapshot);
  }
}

Future<LocalHomeRepository> launch(
  WidgetTester tester, {
  MemorySnapshotStore? store,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = LocalHomeRepository(
    store: store ?? MemorySnapshotStore(),
    initialAppearance: Appearance.light,
  );
  addTearDown(repository.dispose);
  await tester.pumpWidget(HomeSpaceApp(repository: repository));
  await tester.pumpAndSettle();
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

Finder key(String value) => find.byKey(ValueKey(value));

void main() {
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf'))).load();
  });

  testWidgets(
    'Viewer swipes, zooms without paging, exposes details and returns to the library',
    (tester) async {
      await launch(tester);
      await tap(tester, key('memory-media-01'));
      expect(find.byType(MediaViewer), findsOneWidget);
      expect(find.byType(SpaceNavigation), findsNothing);
      expect(find.text('1 / 12'), findsOneWidget);
      await tester.drag(key('viewer-pages'), const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 12'), findsOneWidget);
      expect(find.text('A quiet afternoon by the lake'), findsOneWidget);
      await tap(tester, find.byTooltip('Zoom in'));
      final image = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.semanticLabel == 'A quiet afternoon by the lake',
      );
      final zoom = find.ancestor(
        of: image,
        matching: find.byType(InteractiveViewer),
      );
      expect(
        tester
            .widget<InteractiveViewer>(zoom)
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        greaterThan(2),
      );
      expect(
        tester.widget<PageView>(key('viewer-pages')).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      await tester.drag(key('viewer-pages'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 12'), findsOneWidget);
      await tap(tester, find.byTooltip('Reset zoom'));
      await tap(tester, find.byTooltip('Next photo'));
      expect(find.text('3 / 12'), findsOneWidget);
      await tap(tester, find.byTooltip('Photo details'));
      expect(find.text('Taking the scenic route'), findsWidgets);
      expect(find.text('Little adventures'), findsOneWidget);
      await back(tester);
      await tap(tester, find.byTooltip('Close viewer'));
      expect(find.byType(SpaceNavigation), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Favorite viewer keeps its original sequence when the current favorite changes',
    (tester) async {
      final repository = await launch(tester);
      await tap(tester, find.text('Favorites'));
      await tap(tester, key('memory-media-01'));
      expect(find.text('1 / 3'), findsOneWidget);
      await tap(tester, key('toggle-favorite'));
      expect(repository.favorites.contains('media-01'), isFalse);
      expect(find.text('1 / 3'), findsOneWidget);
      await tap(tester, find.byTooltip('Next photo'));
      expect(find.text('2 / 3'), findsOneWidget);
      await back(tester);
      expect(key('memory-media-01'), findsNothing);
      expect(key('memory-media-02'), findsOneWidget);
    },
  );

  testWidgets(
    'Viewer Trash confirmation can cancel and Undo still works after the viewer closes',
    (tester) async {
      final repository = await launch(tester);
      await tap(tester, key('memory-media-01'));
      await tap(tester, key('trash-memory'));
      await tap(tester, find.text('Cancel'));
      expect(repository.trash, isEmpty);
      expect(find.byType(MediaViewer), findsOneWidget);
      await tap(tester, key('trash-memory'));
      await tap(tester, key('confirm-action'));
      expect(find.byType(MediaViewer), findsNothing);
      expect(repository.trash.map((item) => item.mediaId), ['media-01']);
      await tap(tester, find.text('Undo'));
      expect(repository.trash, isEmpty);
      expect(repository.favorites.contains('media-01'), isTrue);
      expect(key('memory-media-01'), findsOneWidget);
    },
  );

  testWidgets(
    'Photo selection adds several memories to an album and Back exits selection',
    (tester) async {
      final repository = await launch(tester);
      await tester.longPress(key('memory-media-01'));
      await tester.pumpAndSettle();
      await tap(tester, key('memory-media-03'));
      expect(find.text('2 selected'), findsOneWidget);
      await tap(tester, key('bulk-album'));
      await tap(tester, key('add-to-album-family'));
      expect(
        repository.albums
            .singleWhere((album) => album.id == 'album-family')
            .mediaIds
            .contains('media-03'),
        isTrue,
      );
      expect(find.text('2 selected'), findsNothing);
      await tester.longPress(key('memory-media-03'));
      await tester.pumpAndSettle();
      await tap(tester, key('bulk-favorite'));
      expect(repository.favorites.contains('media-03'), isTrue);
      await tester.longPress(key('memory-media-03'));
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.text('1 selected'), findsNothing);
      expect(find.byType(SpaceNavigation), findsOneWidget);
    },
  );

  testWidgets(
    'Trash restores batches and permanently deletes only after confirmation, surviving restart',
    (tester) async {
      final store = MemorySnapshotStore();
      final repository = await launch(tester, store: store);
      await repository.moveManyToTrash(['media-01', 'media-02']);
      await tester.pumpAndSettle();
      await tap(tester, key('tab-profile'));
      await tap(tester, key('trash-setting'));
      await tester.longPress(key('trash-media-01'));
      await tester.pumpAndSettle();
      await tap(tester, key('trash-media-02'));
      await tap(tester, key('restore-selected'));
      expect(repository.trash, isEmpty);
      expect(find.text('Nothing left behind'), findsOneWidget);
      expect(
        repository.albums
            .singleWhere((album) => album.id == 'album-family')
            .mediaIds
            .contains('media-01'),
        isTrue,
      );
      await repository.moveManyToTrash(['media-01', 'media-02']);
      await tester.pumpAndSettle();
      await tap(tester, key('empty-trash'));
      await tap(tester, find.text('Cancel'));
      expect(repository.trash, hasLength(2));
      await tap(tester, key('empty-trash'));
      await tap(tester, key('confirm-action'));
      expect(repository.mediaById('media-01'), isNull);
      expect(find.text('Nothing left behind'), findsOneWidget);
      final restarted = LocalHomeRepository(store: store);
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.mediaById('media-02'), isNull);
      expect(restarted.media, hasLength(10));
    },
  );

  testWidgets(
    'Album details add memories, change cover, edit metadata and delete the album while keeping media',
    (tester) async {
      final repository = await launch(tester);
      await tap(tester, key('tab-collections'));
      await tap(tester, key('album-album-family'));
      await tap(tester, key('add-album-photos'));
      await tap(tester, key('pick-media-02'));
      await tap(tester, key('pick-media-03'));
      await tap(tester, key('save-album-photos'));
      expect(
        repository.albums
            .singleWhere((album) => album.id == 'album-family')
            .mediaIds,
        hasLength(6),
      );
      await tap(tester, find.byTooltip('Select album photos'));
      await tap(tester, key('album-memory-media-01'));
      await tap(tester, key('set-album-cover'));
      expect(
        repository.albums
            .singleWhere((album) => album.id == 'album-family')
            .coverId,
        'media-01',
      );
      await tap(tester, find.byTooltip('Album options'));
      await tap(tester, find.text('Edit album'));
      await tester.enterText(key('album-name'), 'Our people');
      await tester.enterText(key('album-description'), 'Summer together');
      await tap(tester, find.text('Save album'));
      expect(find.text('Our people'), findsOneWidget);
      expect(find.text('Summer together'), findsOneWidget);
      await tap(tester, find.byTooltip('Select album photos'));
      await tap(tester, key('album-memory-media-01'));
      await tap(tester, key('remove-album-photos'));
      await tap(tester, key('confirm-action'));
      expect(repository.mediaById('media-01'), isNotNull);
      expect(
        repository.albums
            .singleWhere((album) => album.id == 'album-family')
            .mediaIds
            .contains('media-01'),
        isFalse,
      );
      await tap(tester, find.byTooltip('Album options'));
      await tap(tester, find.text('Delete album'));
      await tap(tester, key('confirm-action'));
      expect(find.byType(AlbumPage), findsNothing);
      expect(repository.albums, hasLength(3));
      expect(repository.media, hasLength(12));
    },
  );

  testWidgets(
    'Owners change roles and remove or re-add a family member only in the chosen album',
    (tester) async {
      final store = MemorySnapshotStore();
      final repository = await launch(tester, store: store);
      await tap(tester, key('tab-collections'));
      await tap(tester, key('album-album-family'));
      await tap(tester, key('album-members'));
      await tap(tester, key('member-options-member-sam'));
      await tap(tester, find.text('Make contributor'));
      expect(
        repository.albums
            .singleWhere((album) => album.id == 'album-family')
            .roleFor('member-sam'),
        AlbumRole.contributor,
      );
      await tap(tester, key('member-options-member-sam'));
      await tap(tester, find.text('Remove member'));
      await tap(tester, key('confirm-action'));
      await tap(tester, key('add-family-member'));
      await tap(tester, key('choose-member-member-sam'));
      await tap(tester, find.text('Add to this album'));
      expect(
        repository.albums
            .singleWhere((album) => album.id == 'album-family')
            .roleFor('member-sam'),
        AlbumRole.viewer,
      );
      expect(
        repository.albums
            .singleWhere((album) => album.id == 'album-adventures')
            .roleFor('member-sam'),
        isNull,
      );
      expect(
        find.text(
          'Local sharing preview. Changes stay on this device; no invitations are sent.',
        ),
        findsOneWidget,
      );
      final restarted = LocalHomeRepository(store: store);
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(
        restarted.albums
            .singleWhere((album) => album.id == 'album-family')
            .roleFor('member-sam'),
        AlbumRole.viewer,
      );
    },
  );

  testWidgets(
    'Contributor can browse members but cannot edit or remove another member’s addition',
    (tester) async {
      await launch(tester);
      await tap(tester, key('tab-collections'));
      await tap(tester, key('album-album-adventures'));
      expect(find.byTooltip('Album options'), findsNothing);
      await tap(tester, key('album-members'));
      expect(key('member-options-member-alex'), findsNothing);
      expect(key('add-family-member'), findsNothing);
      await back(tester);
      await tap(tester, find.byTooltip('Select album photos'));
      await tap(tester, key('album-memory-media-03'));
      expect(
        tester.widget<OutlinedButton>(key('remove-album-photos')).onPressed,
        isNull,
      );
      expect(key('set-album-cover'), findsNothing);
    },
  );

  testWidgets(
    'Failed Trash deletion keeps selection and saved state, then succeeds on retry',
    (tester) async {
      final store = FlowStore();
      final repository = await launch(tester, store: store);
      await repository.moveToTrash('media-01');
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SpaceNavigation));
      openSpacePage<void>(context, const TrashPage());
      await tester.pumpAndSettle();
      await tester.longPress(key('trash-media-01'));
      await tester.pumpAndSettle();
      store.fail = true;
      await tap(tester, key('delete-selected'));
      await tap(tester, key('confirm-action'));
      expect(find.text('Couldn’t save that change'), findsOneWidget);
      expect(repository.trash, hasLength(1));
      await tap(tester, find.text('OK'));
      expect(find.text('1 selected'), findsOneWidget);
      store.fail = false;
      await tap(tester, key('delete-selected'));
      await tap(tester, key('confirm-action'));
      expect(find.text('Nothing left behind'), findsOneWidget);
      expect(repository.mediaById('media-01'), isNull);
    },
  );

  testWidgets(
    'Bulk Trash keeps navigation usable and a trashed photo restores from its viewer',
    (tester) async {
      final repository = await launch(tester);
      await tester.longPress(key('memory-media-01'));
      await tester.pumpAndSettle();
      await tap(tester, key('memory-media-02'));
      await tap(tester, key('bulk-trash'));
      await tap(tester, key('confirm-action'));
      expect(repository.trash, hasLength(2));
      await tap(tester, key('tab-profile'));
      await tap(tester, key('trash-setting'));
      await tap(tester, key('trash-media-01'));
      expect(key('toggle-favorite'), findsNothing);
      await tap(tester, key('restore-memory'));
      expect(repository.trash.map((entry) => entry.mediaId), ['media-02']);
      expect(repository.favorites.contains('media-01'), isTrue);
      expect(find.byType(TrashPage), findsOneWidget);
    },
  );

  testWidgets(
    'Reduced motion removes route and zoom animation while double-tap zoom and paging work',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await launch(tester);
      await tap(tester, key('memory-media-01'));
      final route = ModalRoute.of(tester.element(find.byType(MediaViewer)))!;
      expect(route.transitionDuration, Duration.zero);
      final center = tester.getCenter(key('viewer-pages'));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reset zoom'), findsOneWidget);
      await tap(tester, find.byTooltip('Reset zoom'));
      await tap(tester, find.byTooltip('Next photo'));
      expect(find.text('2 / 12'), findsOneWidget);
    },
  );

  testWidgets(
    'New flows fit narrow and landscape screens with double-size text',
    (tester) async {
      final repository = await launch(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await repository.moveToTrash('media-03');
      for (final size in [const Size(320, 700), const Size(740, 360)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        var context = tester.element(find.byType(SpaceNavigation));
        openMediaViewer(
          context,
          mediaIds: ['media-01', 'media-02'],
          initialId: 'media-01',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Viewer at $size');
        await tap(tester, find.byTooltip('Photo details'));
        expect(tester.takeException(), isNull, reason: 'Details at $size');
        await back(tester);
        await back(tester);
        context = tester.element(find.byType(SpaceNavigation));
        openSpacePage<void>(context, const AlbumPage(albumId: 'album-family'));
        await tester.pumpAndSettle();
        await tap(tester, key('album-members'));
        expect(tester.takeException(), isNull, reason: 'Members at $size');
        await back(tester);
        await tap(tester, find.byTooltip('Select album photos'));
        expect(
          tester.takeException(),
          isNull,
          reason: 'Album selection at $size',
        );
        await back(tester);
        await back(tester);
        context = tester.element(find.byType(SpaceNavigation));
        openSpacePage<void>(context, const TrashPage());
        await tester.pumpAndSettle();
        await tap(tester, find.byTooltip('Select trashed memories'));
        expect(
          tester.takeException(),
          isNull,
          reason: 'Trash selection at $size',
        );
        await back(tester);
        await back(tester);
        await tap(tester, find.byTooltip('Select photos'));
        expect(
          tester.takeException(),
          isNull,
          reason: 'Library selection at $size',
        );
        await back(tester);
      }
    },
  );

  testWidgets(
    'Viewer and album controls have labels, contrast and Android touch targets',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await launch(tester);
        await tap(tester, key('memory-media-01'));
        for (final guideline in [
          androidTapTargetGuideline,
          labeledTapTargetGuideline,
          textContrastGuideline,
        ]) {
          await expectLater(tester, meetsGuideline(guideline));
        }
        await back(tester);
        await tap(tester, key('tab-collections'));
        await tap(tester, key('album-album-family'));
        await tap(tester, key('album-members'));
        for (final guideline in [
          androidTapTargetGuideline,
          labeledTapTargetGuideline,
          textContrastGuideline,
        ]) {
          await expectLater(tester, meetsGuideline(guideline));
        }
      } finally {
        handle.dispose();
      }
    },
  );
}
