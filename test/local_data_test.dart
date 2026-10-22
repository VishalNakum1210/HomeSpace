import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/seed_library.dart';
import 'package:homespace/data/snapshot_codec.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/domain/repositories.dart';

final fixedNow = DateTime(2026, 10, 22, 15);
LocalHomeRepository local(SnapshotStore store) =>
    LocalHomeRepository(store: store, clock: () => fixedNow);

class FailingStore extends MemorySnapshotStore {
  bool failNext = false;
  @override
  Future<void> save(LibrarySnapshot snapshot) async {
    if (failNext) {
      failNext = false;
      throw const FileSystemException('Simulated full disk');
    }
    await super.save(snapshot);
  }
}

Future<Directory> testDirectory() async {
  final root = Directory('output/test-data').absolute;
  await root.create(recursive: true);
  final directory = await root.createTemp('library-');
  addTearDown(() async {
    if (!await directory.exists()) return;
    final resolvedRoot = await root.resolveSymbolicLinks();
    final resolved = await directory.resolveSymbolicLinks();
    if (!resolved.startsWith('$resolvedRoot${Platform.pathSeparator}')) {
      throw StateError('Test cleanup escaped its output directory.');
    }
    await directory.delete(recursive: true);
  });
  return directory;
}

void main() {
  test('Saved models round-trip with stable IDs, dates, roles, and immutable collections', () {
    final original = seedLibrary(fixedNow);
    final restored = SnapshotCodec.decode(SnapshotCodec.encode(original));
    expect(restored.media.first.id, 'media-01');
    expect(restored.media.first.takenAt, original.media.first.takenAt);
    expect(restored.albums.first.roleFor('member-maya'), AlbumRole.owner);
    expect(restored.albums[1].roleFor('member-maya'), AlbumRole.contributor);
    expect(() => restored.favorites.add('media-07'), throwsUnsupportedError);
    expect(
      () => restored.albums.first.mediaIds.add('media-07'),
      throwsUnsupportedError,
    );
    expect(
      () => restored.albums.first.addedBy['media-07'] = 'member-maya',
      throwsUnsupportedError,
    );
  });

  test('Favorites, theme, profile, albums, membership roles and trash survive a repository restart', () async {
    final store = MemorySnapshotStore();
    final repository = local(store);
    addTearDown(repository.dispose);
    await repository.initialize();
    await repository.toggleFavorite('media-07');
    await repository.setAppearance(Appearance.dark);
    await repository.updateProfile('Anika', AvatarTone.blue);
    final albumId = await repository.createAlbum(
      'Beach days',
      mediaIds: ['media-01', 'media-03'],
    );
    await repository.setMemberRole(albumId, 'member-sam', AlbumRole.viewer);
    await repository.setMemberRole(
      albumId,
      'member-sam',
      AlbumRole.contributor,
    );
    await repository.moveToTrash('media-02');
    final restarted = local(store);
    addTearDown(restarted.dispose);
    await restarted.initialize();
    expect(restarted.profile.name, 'Anika');
    expect(restarted.profile.avatarTone, AvatarTone.blue);
    expect(restarted.profile.appearance, Appearance.dark);
    expect(restarted.favorites, contains('media-07'));
    final album = restarted.albums.singleWhere((item) => item.id == albumId);
    expect(album.mediaIds, ['media-01', 'media-03']);
    expect(album.roleFor('member-sam'), AlbumRole.contributor);
    expect(restarted.trash.single.deletedAt, fixedNow.toUtc());
    expect(restarted.media.any((item) => item.id == 'media-02'), isFalse);
  });

  test(
    'Real file storage survives a new store and repository instance',
    () async {
      final directory = await testDirectory();
      final repository = local(FileSnapshotStore(() async => directory));
      addTearDown(repository.dispose);
      await repository.initialize();
      await repository.setAppearance(Appearance.dark);
      await repository.updateProfile('Family keeper', AvatarTone.purple);
      final restarted = local(
        FileSnapshotStore(() async => Directory(directory.path)),
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.profile.appearance, Appearance.dark);
      expect(restarted.profile.name, 'Family keeper');
      expect(restarted.profile.avatarTone, AvatarTone.purple);
      expect(
        await File('${directory.path}/library.backup.json').exists(),
        isTrue,
      );
    },
  );

  test('Corrupted primary recovers from backup and a subsequent save preserves recovery', () async {
    final directory = await testDirectory();
    final store = FileSnapshotStore(() async => directory);
    final seed = seedLibrary(fixedNow);
    await store.save(seed);
    await store.save(
      seed.copyWith(
        profile: seed.profile.copyWith(appearance: Appearance.dark),
      ),
    );
    await File('${directory.path}/library.json').writeAsString('{broken');
    final recovered = await store.load();
    expect(recovered!.recoveryNotice, isNotNull);
    expect(recovered.snapshot.profile.appearance, Appearance.system);
    final repository = local(store);
    addTearDown(repository.dispose);
    await repository.initialize();
    await repository.toggleFavorite('media-07');
    expect((await store.load())!.snapshot.favorites, contains('media-07'));
    expect(
      (await directory.list().toList()).any(
        (file) => file.path.contains('library.corrupt-'),
      ),
      isTrue,
    );
    final backup = SnapshotCodec.decode(
      await File('${directory.path}/library.backup.json').readAsString(),
    );
    expect(backup.media.length, 12);
  });

  test('Completed pending save recovers a missing primary; valid primary wins over uncommitted pending', () async {
    final directory = await testDirectory();
    final seed = seedLibrary(fixedNow);
    final changed = seed.copyWith(
      profile: seed.profile.copyWith(appearance: Appearance.dark),
    );
    await File('${directory.path}/library.pending.json')
        .writeAsString(SnapshotCodec.encode(changed));
    final store = FileSnapshotStore(() async => directory);
    expect((await store.load())!.snapshot.profile.appearance, Appearance.dark);
    await File('${directory.path}/library.json')
        .writeAsString(SnapshotCodec.encode(seed));
    expect(
      (await store.load())!.snapshot.profile.appearance,
      Appearance.system,
    );
  });

  test(
    'Newer schema is preserved and never replaced by an older backup or write',
    () async {
      final directory = await testDirectory();
      final store = FileSnapshotStore(() async => directory);
      final original = jsonDecode(
        SnapshotCodec.encode(seedLibrary(fixedNow)),
      ) as Map<String, dynamic>;
      original['schemaVersion'] = 99;
      final futureBytes = jsonEncode(original);
      final file = File('${directory.path}/library.json');
      await file.writeAsString(futureBytes);
      await File('${directory.path}/library.backup.json')
          .writeAsString(SnapshotCodec.encode(seedLibrary(fixedNow)));
      await expectLater(
        store.load(),
        throwsA(isA<UnsupportedSnapshotVersion>()),
      );
      await expectLater(
        store.save(seedLibrary(fixedNow)),
        throwsA(isA<UnsupportedSnapshotVersion>()),
      );
      expect(await file.readAsString(), futureBytes);
      final repository = local(store);
      addTearDown(repository.dispose);
      await repository.initialize();
      expect(repository.ready, isFalse);
      expect(repository.bootError, contains('newer HomeSpace'));
    },
  );

  test(
    'Unrecoverable saved data blocks initialization without resetting files',
    () async {
      final directory = await testDirectory();
      final primary = File('${directory.path}/library.json');
      await primary.writeAsString('broken data');
      final repository = local(FileSnapshotStore(() async => directory));
      addTearDown(repository.dispose);
      await repository.initialize();
      expect(repository.ready, isFalse);
      expect(repository.bootError, isNotNull);
      expect(await primary.readAsString(), 'broken data');
    },
  );

  test('Failed write leaves previous state intact and later queued writes still work', () async {
    final store = FailingStore();
    final repository = local(store);
    addTearDown(repository.dispose);
    await repository.initialize();
    store.failNext = true;
    final failed = repository.toggleFavorite('media-01');
    final next = repository.toggleFavorite('media-07');
    await expectLater(failed, throwsA(isA<FileSystemException>()));
    await next;
    expect(repository.favorites, contains('media-01'));
    expect(repository.favorites, contains('media-07'));
    expect(repository.pendingWrites, 0);
    store.failNext = true;
    await expectLater(
      repository.setAppearance(Appearance.dark),
      throwsA(isA<FileSystemException>()),
    );
    expect(repository.profile.appearance, Appearance.system);
    expect(
      SnapshotCodec.decode(store.contents!).profile.appearance,
      Appearance.system,
    );
  });

  test('Concurrent local changes are serialized without losing a favorite or an album', () async {
    final store = MemorySnapshotStore();
    final repository = local(store);
    addTearDown(repository.dispose);
    await repository.initialize();
    await Future.wait([
      repository.toggleFavorite('media-07'),
      repository.toggleFavorite('media-08'),
      repository.createAlbum('Together', mediaIds: ['media-07']).then((_) {}),
      repository.setAppearance(Appearance.dark),
    ]);
    final restored = SnapshotCodec.decode(store.contents!);
    expect(restored.favorites, containsAll(['media-07', 'media-08']));
    expect(restored.albums.last.title, 'Together');
    expect(restored.profile.appearance, Appearance.dark);
  });

  test('Album identity is independent of names and one photo can belong to multiple albums', () async {
    final repository = local(MemorySnapshotStore());
    addTearDown(repository.dispose);
    await repository.initialize();
    final first = await repository.createAlbum(
      'Same name',
      mediaIds: ['media-01'],
    );
    final second = await repository.createAlbum(
      'Same name',
      mediaIds: ['media-01'],
    );
    expect(first, isNot(second));
    await repository.renameAlbum(first, 'Renamed');
    expect(repository.albums.singleWhere((item) => item.id == first).mediaIds, [
      'media-01',
    ]);
    expect(
      repository.albums.singleWhere((item) => item.id == second).title,
      'Same name',
    );
    await repository.removeFromAlbum(first, 'media-01');
    expect(
      repository.albums.singleWhere((item) => item.id == second).mediaIds,
      ['media-01'],
    );
    expect(repository.mediaById('media-01'), isNotNull);
  });

  test(
    'Owner and contributor permissions apply separately to each album',
    () async {
      final repository = local(MemorySnapshotStore());
      addTearDown(repository.dispose);
      await repository.initialize();
      await repository.renameAlbum('album-family', 'Our family');
      await expectLater(
        repository.renameAlbum('album-adventures', 'Not allowed'),
        throwsA(isA<LocalActionException>()),
      );
      await repository.addToAlbum('album-adventures', 'media-01');
      await repository.removeFromAlbum('album-adventures', 'media-01');
      await expectLater(
        repository.removeFromAlbum('album-adventures', 'media-03'),
        throwsA(isA<LocalActionException>()),
      );
      await expectLater(
        repository.setMemberRole(
          'album-adventures',
          'member-sam',
          AlbumRole.viewer,
        ),
        throwsA(isA<LocalActionException>()),
      );
      await expectLater(
        repository.removeMember('album-family', 'member-maya'),
        throwsA(isA<LocalActionException>()),
      );
      await expectLater(
        repository.setMemberRole('album-family', 'member-sam', AlbumRole.owner),
        throwsA(isA<LocalActionException>()),
      );
    },
  );

  test(
    'Viewer cannot add media; membership changes persist per album',
    () async {
      final original = seedLibrary(fixedNow);
      final adventure = original.albums[1].copyWith(
        memberships: [
          const AlbumMembership('member-maya', AlbumRole.viewer),
          const AlbumMembership('member-alex', AlbumRole.owner),
        ],
      );
      final snapshot = original.copyWith(
        albums: [original.albums.first, adventure, ...original.albums.skip(2)],
      );
      final store = MemorySnapshotStore(
        contents: SnapshotCodec.encode(snapshot),
      );
      final repository = local(store);
      addTearDown(repository.dispose);
      await repository.initialize();
      await expectLater(
        repository.addToAlbum('album-adventures', 'media-01'),
        throwsA(isA<LocalActionException>()),
      );
      await repository.setMemberRole(
        'album-family',
        'member-sam',
        AlbumRole.contributor,
      );
      expect(repository.albums[1].roleFor('member-maya'), AlbumRole.viewer);
      final restarted = local(store);
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(
        restarted.albums.first.roleFor('member-sam'),
        AlbumRole.contributor,
      );
      expect(restarted.albums[1].roleFor('member-maya'), AlbumRole.viewer);
    },
  );

  test(
    'Trash restores album membership; permanent deletion cleans all references',
    () async {
      final repository = local(MemorySnapshotStore());
      addTearDown(repository.dispose);
      await repository.initialize();
      await repository.addToAlbum('album-family', 'media-02');
      await repository.moveToTrash('media-02');
      expect(
        repository
            .photosFor(repository.albums.first)
            .any((item) => item.id == 'media-02'),
        isFalse,
      );
      expect(repository.coverFor(repository.albums[2])!.id, isNot('media-02'));
      await repository.restore('media-02');
      expect(
        repository
            .photosFor(repository.albums.first)
            .any((item) => item.id == 'media-02'),
        isTrue,
      );
      await expectLater(
        repository.deletePermanently('media-02'),
        throwsA(isA<LocalActionException>()),
      );
      await repository.moveToTrash('media-02');
      await repository.deletePermanently('media-02');
      expect(repository.mediaById('media-02'), isNull);
      expect(repository.favorites.contains('media-02'), isFalse);
      expect(
        repository.albums.every(
          (album) =>
              !album.mediaIds.contains('media-02') &&
              !album.addedBy.containsKey('media-02'),
        ),
        isTrue,
      );
      SnapshotCodec.validate(repository.snapshot);
    },
  );

  test('Invalid saved references and malformed enum values are rejected', () {
    final json = jsonDecode(
      SnapshotCodec.encode(seedLibrary(fixedNow)),
    ) as Map<String, dynamic>;
    json['favorites'] = ['missing-media'];
    expect(() => SnapshotCodec.decode(jsonEncode(json)), throwsFormatException);
    json['favorites'] = [];
    (json['profile'] as Map<String, dynamic>)['appearance'] = 'invalid-theme';
    expect(() => SnapshotCodec.decode(jsonEncode(json)), throwsFormatException);
  });

  test('Empty and offline fixtures preserve actual saved local data', () async {
    final store = MemorySnapshotStore();
    final repository = local(store);
    addTearDown(repository.dispose);
    await repository.initialize();
    await repository.toggleFavorite('media-07');
    final saved = store.contents;
    for (final scenario in DemoScenario.values) {
      repository.setScenario(scenario);
      if (scenario == DemoScenario.empty) {
        expect(repository.media, isEmpty);
        expect(repository.albums, isEmpty);
      }
      expect(store.contents, saved);
    }
    repository.setScenario(DemoScenario.populated);
    expect(repository.media.length, 12);
    expect(repository.favorites, contains('media-07'));
  });

  test(
    'Date groups use persisted timestamps instead of frozen Today labels',
    () {
      final item = seedLibrary(fixedNow).media.first;
      expect(item.dateLabel(fixedNow), 'Today');
      expect(
        item.dateLabel(fixedNow.add(const Duration(days: 1))),
        'Yesterday',
      );
      expect(
        item.dateLabel(fixedNow.add(const Duration(days: 2))),
        '22 Oct 2026',
      );
    },
  );
}
