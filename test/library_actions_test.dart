import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/domain/repositories.dart';

class RejectBatchStore extends MemorySnapshotStore {
  bool fail = false;
  @override
  Future<void> save(LibrarySnapshot snapshot) async {
    if (fail) throw const FileSystemException('Disk full');
    return super.save(snapshot);
  }
}

Future<LocalHomeRepository> library({SnapshotStore? store}) async {
  final repository = LocalHomeRepository(store: store ?? MemorySnapshotStore());
  addTearDown(repository.dispose);
  await repository.initialize();
  return repository;
}

void main() {
  test(
    'Bulk favorites are idempotent and reject an invalid selection atomically',
    () async {
      final store = MemorySnapshotStore();
      final repository = await library(store: store);
      await repository.setFavorites(['media-01', 'media-03', 'media-03'], true);
      expect(
        repository.favorites.containsAll(['media-01', 'media-03']),
        isTrue,
      );
      final saved = store.contents;
      await expectLater(
        repository.setFavorites(['media-01', 'missing'], false),
        throwsA(isA<LocalActionException>()),
      );
      expect(store.contents, saved);
      await repository.setFavorites(['media-01', 'media-03'], false);
      expect(
        repository.favorites.intersection({'media-01', 'media-03'}),
        isEmpty,
      );
    },
  );

  test(
    'Bulk Trash copies arguments and restore keeps albums and favorites',
    () async {
      final repository = await library();
      final albums = repository.albums.map((album) => album.mediaIds).toList();
      final favorites = repository.favorites;
      final ids = ['media-01', 'media-02', 'media-01'];
      final pending = repository.moveManyToTrash(ids);
      ids.clear();
      await pending;
      expect(repository.trash.map((entry) => entry.mediaId).toSet(), {
        'media-01',
        'media-02',
      });
      expect(
        repository.trash.map((entry) => entry.deletedAt).toSet(),
        hasLength(1),
      );
      expect(repository.media, hasLength(10));
      await repository.restoreMany(['media-01', 'media-02']);
      expect(repository.media, hasLength(12));
      expect(repository.albums.map((album) => album.mediaIds), albums);
      expect(repository.favorites, favorites);
    },
  );

  test('Permanent bulk deletion requires every item in Trash and cleans all references', () async {
    final repository = await library();
    await repository.moveToTrash('media-01');
    await expectLater(
      repository.deleteManyPermanently(['media-01', 'media-02']),
      throwsA(isA<LocalActionException>()),
    );
    expect(repository.mediaById('media-01'), isNotNull);
    await repository.moveToTrash('media-02');
    await repository.deleteManyPermanently(['media-01', 'media-02']);
    expect(repository.trash, isEmpty);
    for (final id in ['media-01', 'media-02']) {
      expect(repository.mediaById(id), isNull);
      expect(repository.favorites.contains(id), isFalse);
      for (final album in repository.albums) {
        expect(album.mediaIds.contains(id), isFalse);
        expect(album.addedBy.containsKey(id), isFalse);
        expect(album.coverId, isNot(id));
      }
    }
  });

  test(
    'Failed bulk saves keep every item unchanged and allow a later retry',
    () async {
      final store = RejectBatchStore();
      final repository = await library(store: store);
      final saved = store.contents;
      store.fail = true;
      await expectLater(
        repository.moveManyToTrash(['media-01', 'media-02']),
        throwsA(isA<FileSystemException>()),
      );
      expect(repository.trash, isEmpty);
      expect(repository.media, hasLength(12));
      expect(store.contents, saved);
      expect(repository.pendingWrites, 0);
      store.fail = false;
      await repository.moveManyToTrash(['media-01', 'media-02']);
      final restarted = await library(store: store);
      expect(restarted.trash, hasLength(2));
    },
  );

  test('Album bulk additions preserve attribution and mixed contributor removal rejects the whole selection', () async {
    final repository = await library();
    await repository.addManyToAlbum('album-adventures', [
      'media-01',
      'media-02',
      'media-01',
    ]);
    var album = repository.albums.singleWhere(
      (item) => item.id == 'album-adventures',
    );
    expect(album.mediaIds, hasLength(6));
    expect(album.addedBy['media-01'], repository.profile.userId);
    await expectLater(
      repository.removeManyFromAlbum(album.id, ['media-01', 'media-03']),
      throwsA(isA<LocalActionException>()),
    );
    album = repository.albums.singleWhere((item) => item.id == album.id);
    expect(
      album.mediaIds.toSet().containsAll(['media-01', 'media-03']),
      isTrue,
    );
    await repository.removeManyFromAlbum(album.id, ['media-01', 'media-02']);
    expect(
      repository.albums.singleWhere((item) => item.id == album.id).mediaIds,
      hasLength(4),
    );
    expect(repository.media, hasLength(12));
  });

  test('Album edits, cover changes, and deletion require an owner and valid active membership', () async {
    final repository = await library();
    for (final action in [
      () => repository.updateAlbum('album-adventures', 'Changed', ''),
      () => repository.deleteAlbum('album-adventures'),
      () => repository.setAlbumCover('album-adventures', 'media-03'),
      () => repository.setAlbumCover('album-family', 'media-03'),
    ]) {
      await expectLater(action(), throwsA(isA<LocalActionException>()));
    }
    await repository.moveToTrash('media-01');
    await expectLater(
      repository.setAlbumCover('album-family', 'media-01'),
      throwsA(isA<LocalActionException>()),
    );
    expect(
      repository.albums
          .singleWhere((album) => album.id == 'album-adventures')
          .title,
      'Little adventures',
    );
  });

  test('Edited album and cover survive restart; deleting an album keeps its photos elsewhere', () async {
    final store = MemorySnapshotStore();
    final repository = await library(store: store);
    await repository.updateAlbum(
      'album-family',
      ' Our people ',
      ' Summer together ',
    );
    await repository.setAlbumCover('album-family', 'media-08');
    final restarted = await library(store: store);
    final album = restarted.albums.singleWhere(
      (item) => item.id == 'album-family',
    );
    expect(album.title, 'Our people');
    expect(album.description, 'Summer together');
    expect(album.coverId, 'media-08');
    await restarted.deleteAlbum(album.id);
    expect(restarted.media, hasLength(12));
    expect(restarted.favorites.contains('media-01'), isTrue);
    expect(
      restarted.albums
          .singleWhere((item) => item.id == 'album-everyday')
          .mediaIds
          .contains('media-01'),
      isTrue,
    );
    final again = await library(store: store);
    expect(again.albums.any((item) => item.id == album.id), isFalse);
  });
}
