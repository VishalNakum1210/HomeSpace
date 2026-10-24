import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/domain/repositories.dart';

class EditorStore extends MemorySnapshotStore {
  bool fail = false;
  int writes = 0;
  @override
  Future<void> save(LibrarySnapshot snapshot) async {
    writes++;
    if (fail) throw const FileSystemException('Simulated full disk');
    await super.save(snapshot);
  }
}

Future<LocalHomeRepository> open(EditorStore store) async {
  final repository = LocalHomeRepository(store: store);
  addTearDown(repository.dispose);
  await repository.initialize();
  return repository;
}

void main() {
  test('Creation copies photo arguments and commits an explicit cover in one write', () async {
    final store = EditorStore();
    final repository = await open(store);
    final writes = store.writes;
    final ids = ['media-01', 'media-02'];
    final saving = repository.createAlbum(
      'Summer',
      mediaIds: ids,
      coverId: 'media-02',
    );
    ids.clear();
    final id = await saving;
    expect(store.writes, writes + 1);
    final album = repository.albums.singleWhere((album) => album.id == id);
    expect(album.mediaIds, ['media-01', 'media-02']);
    expect(album.coverId, 'media-02');
    expect(album.addedBy.values.toSet(), {repository.profile.userId});
    final restored = await open(store);
    expect(
      restored.albums.singleWhere((album) => album.id == id).coverId,
      'media-02',
    );
  });

  test(
    'Invalid cover and contributor edits reject all metadata without saving',
    () async {
      final store = EditorStore();
      final repository = await open(store);
      final before = repository.snapshot;
      final writes = store.writes;
      await expectLater(
        repository.createAlbum(
          'Invalid',
          mediaIds: ['media-01'],
          coverId: 'media-03',
        ),
        throwsA(isA<LocalActionException>()),
      );
      await expectLater(
        repository.updateAlbum(
          'album-family',
          'Wrong',
          'Wrong',
          coverId: 'media-03',
        ),
        throwsA(isA<LocalActionException>()),
      );
      await expectLater(
        repository.updateAlbum(
          'album-adventures',
          'Wrong',
          'Wrong',
          coverId: 'media-03',
        ),
        throwsA(isA<LocalActionException>()),
      );
      expect(repository.snapshot, same(before));
      expect(store.writes, writes);
      await repository.moveToTrash('media-04');
      final trashed = repository.snapshot;
      await expectLater(
        repository.updateAlbum(
          'album-family',
          'Wrong',
          'Wrong',
          coverId: 'media-04',
        ),
        throwsA(isA<LocalActionException>()),
      );
      expect(repository.snapshot, same(trashed));
    },
  );

  test('Title description and cover roll back together on failure and survive retry/restart', () async {
    final store = EditorStore();
    final repository = await open(store);
    final before = repository.snapshot;
    store.fail = true;
    await expectLater(
      repository.updateAlbum(
        'album-family',
        'Together',
        'Our summer',
        coverId: 'media-04',
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(repository.snapshot, same(before));
    store.fail = false;
    final writes = store.writes;
    await repository.updateAlbum(
      'album-family',
      'Together',
      'Our summer',
      coverId: 'media-04',
    );
    expect(store.writes, writes + 1);
    final restored = await open(store);
    final album = restored.albums.singleWhere(
      (album) => album.id == 'album-family',
    );
    expect(album.title, 'Together');
    expect(album.description, 'Our summer');
    expect(album.coverId, 'media-04');
    expect(album.mediaIds, before.albums.first.mediaIds);
  });
}
