import 'dart:async';

import '../domain/models.dart';
import '../domain/repositories.dart';
import 'seed_library.dart';
import 'snapshot_codec.dart';
import 'snapshot_store.dart';
import 'demo_remote_repositories.dart';

class LocalHomeRepository extends HomeRepository {
  final SnapshotStore store;
  final DateTime Function() clock;
  final Appearance initialAppearance;
  LibrarySnapshot _data;
  DemoScenario _scenario;
  bool _ready = false;
  bool _disposed = false;
  String? _bootError;
  String? _recoveryNotice;
  int _pendingWrites = 0;
  int _idCounter = 0;
  Future<void>? _initializing;
  Future<void> _tail = Future.value();
  late final DemoConnectionRepository _connection = DemoConnectionRepository(
    scenario: _scenario,
  );
  late final DemoUploadRepository _uploads = DemoUploadRepository(
    scenario: _scenario,
  );

  LocalHomeRepository({
    required this.store,
    DateTime Function()? clock,
    this._scenario = DemoScenario.populated,
    this.initialAppearance = Appearance.system,
  }) : clock = clock ?? DateTime.now,
       _data = seedLibrary((clock ?? DateTime.now)());

  @override
  bool get ready => _ready;
  @override
  String? get bootError => _bootError;
  @override
  String? get recoveryNotice => _recoveryNotice;
  @override
  int get pendingWrites => _pendingWrites;
  @override
  DemoScenario get scenario => _scenario;
  @override
  ConnectionRepository get connection => _connection;
  @override
  UploadRepository get uploads => _uploads;
  @override
  ProfileSettings get profile => _data.profile;
  @override
  LibrarySnapshot get snapshot => _scenario == DemoScenario.empty
      ? _data.copyWith(media: [], albums: [], favorites: {}, trash: [])
      : _data;
  @override
  List<MediaItem> get media {
    final trashed = trash.map((item) => item.mediaId).toSet();
    return List.unmodifiable(
      snapshot.media.where((item) => !trashed.contains(item.id)),
    );
  }

  @override
  Set<String> get favorites => snapshot.favorites;
  @override
  List<TrashEntry> get trash => snapshot.trash;
  @override
  List<Album> get albums => snapshot.albums;

  @override
  Future<void> initialize() =>
      _ready ? Future.value() : _initializing ??= _load();

  Future<void> _load() async {
    _bootError = null;
    _notify();
    try {
      final saved = await store.load();
      if (saved == null) {
        final seed = seedLibrary(clock());
        _data = seed.copyWith(
          profile: seed.profile.copyWith(appearance: initialAppearance),
        );
        await store.save(_data);
      } else {
        _data = saved.snapshot;
        _recoveryNotice = saved.recoveryNotice;
      }
      _ready = true;
    } on UnsupportedSnapshotVersion catch (error) {
      _bootError = error.toString();
    } catch (_) {
      _bootError = 'Couldn’t open your saved library. Your saved files have been kept. Please retry.';
    } finally {
      _initializing = null;
      _notify();
    }
  }

  @override
  void setScenario(DemoScenario scenario) {
    _scenario = scenario;
    _connection.scenario = scenario;
    _connection.disconnect();
    _uploads.reset(scenario);
    _notify();
  }

  @override
  String groupFor(MediaItem item) => item.dateLabel(clock());

  @override
  MediaItem? mediaById(String id) {
    for (final item in snapshot.media) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  FamilyMember memberById(String id) {
    if (id == profile.userId) return FamilyMember(id, profile.name);
    return _data.family.firstWhere(
      (item) => item.id == id,
      orElse: () => throw const LocalActionException(
        'That family member is unavailable.',
      ),
    );
  }

  @override
  List<MediaItem> photosFor(Album album) {
    final visible = {for (final item in media) item.id: item};
    return List.unmodifiable([
      for (final id in album.mediaIds)
        if (visible[id] != null) visible[id]!,
    ]);
  }

  @override
  MediaItem? coverFor(Album album) {
    final photos = photosFor(album);
    for (final photo in photos) {
      if (photo.id == album.coverId) return photo;
    }
    return photos.firstOrNull;
  }

  Future<void> _commit(LibrarySnapshot Function(LibrarySnapshot) change) {
    _pendingWrites++;
    _notify();
    final operation = _tail
        .then((_) async {
          if (!_ready) {
            throw const LocalActionException('Your library is still opening.');
          }
          final next = change(_data);
          SnapshotCodec.validate(next);
          await store.save(next);
          _data = next;
          _notify();
        })
        .whenComplete(() {
          _pendingWrites--;
          _notify();
        });
    // Recover the queue after one rejected write; the caller still receives it.
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  MediaItem _requireMedia(LibrarySnapshot state, String id) =>
      state.media.firstWhere(
        (item) => item.id == id,
        orElse: () =>
            throw const LocalActionException('That memory is unavailable.'),
      );
  Album _album(LibrarySnapshot state, String id) => state.albums.firstWhere(
    (item) => item.id == id,
    orElse: () =>
        throw const LocalActionException('That album is unavailable.'),
  );
  void _owner(LibrarySnapshot state, Album album) {
    if (album.roleFor(state.profile.userId) != AlbumRole.owner) {
      throw const LocalActionException('Only the album owner can change this.');
    }
  }

  String _name(String value, int limit) {
    final name = value.trim();
    if (name.isEmpty || name.length > limit) {
      throw LocalActionException(
        'Enter a name between 1 and $limit characters.',
      );
    }
    return name;
  }

  LibrarySnapshot _replace(LibrarySnapshot state, Album album) =>
      state.copyWith(
        albums: [
          for (final item in state.albums) item.id == album.id ? album : item,
        ],
      );

  @override
  Future<void> toggleFavorite(String id) => _commit((state) {
    _requireMedia(state, id);
    if (state.trash.any((entry) => entry.mediaId == id)) {
      throw const LocalActionException('Restore this memory first.');
    }
    final next = {...state.favorites};
    next.contains(id) ? next.remove(id) : next.add(id);
    return state.copyWith(favorites: next);
  });

  List<String> _activeIds(LibrarySnapshot state, Iterable<String> ids) {
    final unique = ids.toSet().toList();
    for (final id in unique) {
      _requireMedia(state, id);
      if (state.trash.any((entry) => entry.mediaId == id)) {
        throw const LocalActionException('Restore this memory first.');
      }
    }
    return unique;
  }

  @override
  Future<void> setFavorites(List<String> ids, bool favorite) {
    final requested = List<String>.of(ids);
    return _commit((state) {
      final active = _activeIds(state, requested);
      final next = {...state.favorites};
      favorite ? next.addAll(active) : next.removeAll(active);
      return state.copyWith(favorites: next);
    });
  }

  @override
  Future<void> setAppearance(Appearance appearance) => _commit(
    (state) =>
        state.copyWith(profile: state.profile.copyWith(appearance: appearance)),
  );

  @override
  Future<void> updateProfile(String name, AvatarTone tone) => _commit(
    (state) => state.copyWith(
      profile: state.profile.copyWith(name: _name(name, 60), avatarTone: tone),
    ),
  );

  @override
  Future<String> createAlbum(
    String title, {
    String description = '',
    List<String> mediaIds = const [],
    String? coverId,
  }) async {
    final requested = List<String>.of(mediaIds);
    String? createdId;
    await _commit((state) {
      final name = _name(title, 80);
      if (description.length > 4096) {
        throw const LocalActionException(
          'Keep album descriptions under 4096 characters.',
        );
      }
      final photos = requested.toSet().toList();
      for (final id in photos) {
        _requireMedia(state, id);
        if (state.trash.any((entry) => entry.mediaId == id)) {
          throw const LocalActionException(
            'Restore trashed memories before adding them.',
          );
        }
      }
      if (coverId != null && !photos.contains(coverId)) {
        throw const LocalActionException(
          'Add the cover photo to this album first.',
        );
      }
      do {
        createdId = 'album-${clock().microsecondsSinceEpoch}-${_idCounter++}';
      } while (state.albums.any((item) => item.id == createdId));
      final album = Album(
        id: createdId!,
        title: name,
        description: description.trim(),
        mediaIds: photos,
        coverId: coverId ?? photos.firstOrNull,
        memberships: [AlbumMembership(state.profile.userId, AlbumRole.owner)],
        addedBy: {for (final id in photos) id: state.profile.userId},
      );
      return state.copyWith(albums: [...state.albums, album]);
    });
    return createdId!;
  }

  @override
  Future<void> renameAlbum(String id, String title) => _commit((state) {
    final album = _album(state, id);
    _owner(state, album);
    return _replace(state, album.copyWith(title: _name(title, 80)));
  });

  @override
  Future<void> updateAlbum(
    String id,
    String title,
    String description, {
    String? coverId,
  }) => _commit((state) {
    final album = _album(state, id);
    _owner(state, album);
    if (coverId != null) {
      _activeIds(state, [coverId]);
      if (!album.mediaIds.contains(coverId)) {
        throw const LocalActionException(
          'Add the cover photo to this album first.',
        );
      }
    }
    if (description.length > 4096) {
      throw const LocalActionException(
        'Keep descriptions under 4096 characters.',
      );
    }
    return _replace(
      state,
      album.copyWith(
        title: _name(title, 80),
        description: description.trim(),
        coverId: coverId,
      ),
    );
  });

  @override
  Future<void> deleteAlbum(String id) => _commit((state) {
    _owner(state, _album(state, id));
    return state.copyWith(
      albums: state.albums.where((album) => album.id != id).toList(),
    );
  });

  @override
  Future<void> setAlbumCover(String albumId, String mediaId) => _commit((
    state,
  ) {
    final album = _album(state, albumId);
    _owner(state, album);
    _activeIds(state, [mediaId]);
    if (!album.mediaIds.contains(mediaId)) {
      throw const LocalActionException('Add this memory to the album first.');
    }
    return _replace(state, album.copyWith(coverId: mediaId));
  });

  @override
  Future<void> addToAlbum(String albumId, String mediaId) =>
      addManyToAlbum(albumId, [mediaId]);

  @override
  Future<void> addManyToAlbum(String albumId, List<String> mediaIds) {
    final requested = List<String>.of(mediaIds);
    return _commit((state) {
      final album = _album(state, albumId);
      final ids = _activeIds(state, requested);
      final role = album.roleFor(state.profile.userId);
      if (role != AlbumRole.owner && role != AlbumRole.contributor) {
        throw const LocalActionException('This album is view-only.');
      }
      final additions = ids
          .where((id) => !album.mediaIds.contains(id))
          .toList();
      return _replace(
        state,
        album.copyWith(
          mediaIds: [...album.mediaIds, ...additions],
          coverId: album.coverId ?? additions.firstOrNull,
          addedBy: {
            ...album.addedBy,
            for (final id in additions) id: state.profile.userId,
          },
        ),
      );
    });
  }

  @override
  Future<void> removeFromAlbum(String albumId, String mediaId) =>
      removeManyFromAlbum(albumId, [mediaId]);

  @override
  Future<void> removeManyFromAlbum(String albumId, List<String> mediaIds) {
    final requested = mediaIds.toSet();
    return _commit((state) {
      final album = _album(state, albumId);
      final role = album.roleFor(state.profile.userId);
      if (role != AlbumRole.owner &&
          !(role == AlbumRole.contributor &&
              requested.every(
                (id) => album.addedBy[id] == state.profile.userId,
              ))) {
        throw const LocalActionException(
          'You can only remove your own additions.',
        );
      }
      final ids = album.mediaIds
          .where((id) => !requested.contains(id))
          .toList();
      final additions = {...album.addedBy}
        ..removeWhere((id, _) => requested.contains(id));
      return _replace(
        state,
        album.copyWith(
          mediaIds: ids,
          addedBy: additions,
          coverId: requested.contains(album.coverId)
              ? ids.firstOrNull
              : album.coverId,
          clearCover: ids.isEmpty,
        ),
      );
    });
  }

  @override
  Future<void> setMemberRole(
    String albumId,
    String userId,
    AlbumRole role,
  ) => _commit((state) {
    final album = _album(state, albumId);
    _owner(state, album);
    memberById(userId);
    if (role == AlbumRole.owner || album.roleFor(userId) == AlbumRole.owner) {
      throw const LocalActionException(
        'The album must keep its current owner.',
      );
    }
    final members =
        album.memberships.where((member) => member.userId != userId).toList()
          ..add(AlbumMembership(userId, role));
    return _replace(state, album.copyWith(memberships: members));
  });

  @override
  Future<void> removeMember(String albumId, String userId) => _commit((state) {
    final album = _album(state, albumId);
    _owner(state, album);
    if (album.roleFor(userId) == AlbumRole.owner) {
      throw const LocalActionException('The album owner cannot be removed.');
    }
    return _replace(
      state,
      album.copyWith(
        memberships: album.memberships
            .where((member) => member.userId != userId)
            .toList(),
      ),
    );
  });

  @override
  Future<void> moveToTrash(String id) => moveManyToTrash([id]);

  @override
  Future<void> moveManyToTrash(List<String> ids) {
    final requested = ids.toSet();
    return _commit((state) {
      for (final id in requested) {
        _requireMedia(state, id);
      }
      final existing = state.trash.map((entry) => entry.mediaId).toSet();
      final deletedAt = clock().toUtc();
      return state.copyWith(
        trash: [
          ...state.trash,
          for (final id in requested.difference(existing))
            TrashEntry(id, deletedAt),
        ],
      );
    });
  }

  @override
  Future<void> restore(String id) => restoreMany([id]);

  @override
  Future<void> restoreMany(List<String> ids) {
    final requested = ids.toSet();
    return _commit((state) {
      for (final id in requested) {
        _requireMedia(state, id);
      }
      return state.copyWith(
        trash: state.trash
            .where((entry) => !requested.contains(entry.mediaId))
            .toList(),
      );
    });
  }

  @override
  Future<void> deletePermanently(String id) => deleteManyPermanently([id]);

  @override
  Future<void> deleteManyPermanently(List<String> ids) {
    final requested = ids.toSet();
    return _commit((state) {
      final trashed = state.trash.map((entry) => entry.mediaId).toSet();
      if (!trashed.containsAll(requested)) {
        throw const LocalActionException('Move this memory to Trash first.');
      }
      return state.copyWith(
        media: state.media
            .where((item) => !requested.contains(item.id))
            .toList(),
        favorites: {...state.favorites}..removeAll(requested),
        trash: state.trash
            .where((entry) => !requested.contains(entry.mediaId))
            .toList(),
        albums: [
          for (final album in state.albums)
            () {
              final ids = album.mediaIds
                  .where((value) => !requested.contains(value))
                  .toList();
              return album.copyWith(
                mediaIds: ids,
                addedBy: {...album.addedBy}
                  ..removeWhere((id, _) => requested.contains(id)),
                coverId: requested.contains(album.coverId)
                    ? ids.firstOrNull
                    : album.coverId,
                clearCover: ids.isEmpty,
              );
            }(),
        ],
      );
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connection.dispose();
    _uploads.dispose();
    super.dispose();
  }
}
