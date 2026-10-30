import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/album_page.dart';
import 'package:homespace/pages/album_members_page.dart';

class PendingStore extends MemorySnapshotStore {
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<void> save(LibrarySnapshot snapshot) async {
    if (gate != null) await gate!.future;
    if (fail) throw const FileSystemException('Disk full');
    await super.save(snapshot);
  }
}

Finder key(String value) => find.byKey(ValueKey(value));

Future<void> tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<LocalHomeRepository> start(
  WidgetTester tester,
  PendingStore store,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = LocalHomeRepository(
    store: store,
    initialAppearance: Appearance.light,
  );
  addTearDown(repository.dispose);
  await tester.pumpWidget(HomeSpaceApp(repository: repository));
  await tester.pumpAndSettle();
  await tap(tester, key('tab-collections'));
  await tap(tester, key('album-album-family'));
  return repository;
}

Future<void> editAlbum(WidgetTester tester) async {
  await tap(tester, find.byTooltip('Album options'));
  await tap(tester, find.text('Edit album'));
  await tester.enterText(key('album-name'), 'Saved while leaving');
}

void main() {
  testWidgets('A completed bulk action does not clear a new photo selection', (
    tester,
  ) async {
    final store = PendingStore();
    final repository = await start(tester, store);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.longPress(key('memory-media-01'));
    await tester.pumpAndSettle();
    store.gate = Completer<void>();
    await tester.tap(key('bulk-favorite'));
    await tester.pump();
    expect(repository.pendingWrites, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.longPress(key('memory-media-03'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A save completing during editor Back does not close its album', (
    tester,
  ) async {
    final store = PendingStore();
    final repository = await start(tester, store);
    await editAlbum(tester);
    store.gate = Completer<void>();
    await tester.tap(find.text('Save album'));
    await tester.pump();
    expect(repository.pendingWrites, 1);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 20));
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.text('Saved while leaving'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A failed save after editor Back does not show a dialog on another page',
    (tester) async {
      final store = PendingStore();
      final repository = await start(tester, store);
      await editAlbum(tester);
      store.gate = Completer<void>();
      store.fail = true;
      await tester.tap(find.text('Save album'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 20));
      store.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AlbumPage), findsOneWidget);
      expect(
        repository.albums
            .singleWhere((album) => album.id == 'album-family')
            .title,
        'Family weekends',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A permission save completing during sheet dismissal keeps Members open',
    (tester) async {
      final store = PendingStore();
      final repository = await start(tester, store);
      await tap(tester, key('album-members'));
      await tap(tester, key('member-options-member-sam'));
      await tap(tester, key('permission-contributor'));
      store.gate = Completer<void>();
      await tester.tap(key('save-member-permissions'));
      await tester.pump();
      expect(repository.pendingWrites, 1);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 20));
      store.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlbumMembersPage), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        repository.albums
            .singleWhere((album) => album.id == 'album-family')
            .roleFor('member-sam'),
        AlbumRole.contributor,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
