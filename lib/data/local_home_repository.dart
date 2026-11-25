import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../application/auto_backup_service.dart';
import '../domain/models.dart';
import '../domain/pin_security.dart';
import '../domain/repositories.dart';
import 'demo_remote_repositories.dart';
import 'homespace_api_client.dart';
import 'seed_library.dart';
import 'snapshot_codec.dart';
import 'snapshot_store.dart';

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
  final ConnectionRepository? customConnection;
  final UploadRepository? customUploads;
  final Uri? Function()? getServerAddress;
  final String? Function()? getAuthToken;
  final HomeSpaceApiClient _apiClient;
  final bool _ownsApiClient;
  late final ConnectionRepository _connection = customConnection ??
      DemoConnectionRepository(scenario: _scenario);
  late final UploadRepository _uploads = customUploads ??
      DemoUploadRepository(scenario: _scenario);

  LocalHomeRepository({
    required this.store,
    DateTime Function()? clock,
    this.customConnection,
    this.customUploads,
    this.getServerAddress,
    this.getAuthToken,
    HomeSpaceApiClient? apiClient,
    this._scenario = DemoScenario.populated,
    this.initialAppearance = Appearance.system,
  }) : clock = clock ?? DateTime.now,
       _ownsApiClient = apiClient == null,
       _apiClient = apiClient ?? HomeSpaceApiClient(),
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
    final conn = _connection;
    if (conn is DemoConnectionRepository) {
      conn.scenario = scenario;
      conn.disconnect();
    }
    final up = _uploads;
    if (up is DemoUploadRepository) {
      up.reset(scenario);
    }
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
    for (final item in _data.family) {
      if (item.id == id) return item;
    }
    return FamilyMember(id, 'Family Member');
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
  Future<void> addMedia(MediaItem item) => _commit((state) {
    bool matches(MediaItem m) =>
        m.id == item.id ||
        (m.title.toLowerCase() == item.title.toLowerCase() && m.title.isNotEmpty);
    final oldItem = state.media.cast<MediaItem?>().firstWhere(
      (m) => m != null && matches(m),
      orElse: () => null,
    );
    if (oldItem != null) {
      final oldId = oldItem.id;
      final newId = item.id;
      final nextFavorites = {...state.favorites};
      if (oldId != newId && nextFavorites.remove(oldId)) {
        nextFavorites.add(newId);
      }
      final nextAlbums = oldId == newId
          ? state.albums
          : state.albums.map((a) {
              final nextMediaIds = a.mediaIds.map((id) => id == oldId ? newId : id).toList();
              final nextCover = a.coverId == oldId ? newId : a.coverId;
              final nextAddedBy = <String, String>{};
              a.addedBy.forEach((key, val) {
                nextAddedBy[key == oldId ? newId : key] = val;
              });
              return a.copyWith(mediaIds: nextMediaIds, coverId: nextCover, addedBy: nextAddedBy);
            }).toList();
      final nextTrash = oldId == newId
          ? state.trash
          : state.trash.map((t) => t.mediaId == oldId ? TrashEntry(newId, t.deletedAt) : t).toList();
      return state.copyWith(
        media: state.media.map((m) => matches(m) ? item : m).toList(),
        favorites: nextFavorites,
        albums: nextAlbums,
        trash: nextTrash,
      );
    }
    return state.copyWith(media: [item, ...state.media]);
  });

  @override
  Future<void> addMediaItems(List<MediaItem> items) => _commit((state) {
    final existingIds = state.media.map((m) => m.id).toSet();
    final existingTitles = state.media.map((m) => m.title.toLowerCase()).toSet();
    final newItems = items
        .where((m) =>
            !existingIds.contains(m.id) &&
            !existingTitles.contains(m.title.toLowerCase()))
        .toList();
    if (newItems.isEmpty) return state;
    return state.copyWith(media: [...newItems, ...state.media]);
  });

  Future<void> initForAuthenticatedUser({
    required String userId,
    required String name,
    required AvatarTone avatarTone,
    bool? isAdmin,
    bool clearDemoSeed = false,
    Uri? serverUri,
    String? token,
  }) async {
    await _commit((state) {
      final oldUserId = state.profile.userId;
      final seed = clearDemoSeed ? seedLibrary(clock()) : null;
      final seedMediaIds = seed == null ? const <String>{} : seed.media.map((m) => m.id).toSet();
      final seedAlbumIds = seed == null ? const <String>{} : seed.albums.map((a) => a.id).toSet();

      final baseMedia = clearDemoSeed
          ? state.media.where((m) => !seedMediaIds.contains(m.id)).toList()
          : state.media;
      final keptMediaIds = {for (final m in baseMedia) m.id};

      final baseFavorites = clearDemoSeed
          ? state.favorites.where(keptMediaIds.contains).toSet()
          : state.favorites;
      final baseTrash = clearDemoSeed
          ? state.trash.where((t) => keptMediaIds.contains(t.mediaId)).toList()
          : state.trash;
      final baseAlbums = clearDemoSeed
          ? state.albums.where((a) => !seedAlbumIds.contains(a.id)).toList()
          : state.albums;

      final updatedAlbums = baseAlbums.map((album) {
        final nextMediaIds = clearDemoSeed
            ? album.mediaIds.where(keptMediaIds.contains).toList()
            : album.mediaIds;
        final updatedMemberships = album.memberships.map((m) {
          if (m.userId == oldUserId) {
            return AlbumMembership(userId, m.role);
          }
          return m;
        }).toList();
        final updatedAddedBy = <String, String>{};
        album.addedBy.forEach((mediaId, adderId) {
          if (nextMediaIds.contains(mediaId)) {
            updatedAddedBy[mediaId] = adderId == oldUserId ? userId : adderId;
          }
        });
        final nextCover = album.coverId != null && nextMediaIds.contains(album.coverId)
            ? album.coverId
            : nextMediaIds.firstOrNull;
        return album.copyWith(
          mediaIds: nextMediaIds,
          coverId: nextCover,
          clearCover: nextMediaIds.isEmpty,
          memberships: updatedMemberships,
          addedBy: updatedAddedBy,
        );
      }).toList();

      return state.copyWith(
        media: baseMedia,
        favorites: baseFavorites,
        trash: baseTrash,
        profile: state.profile.copyWith(
          userId: userId,
          name: name,
          avatarTone: avatarTone,
          isAdmin: isAdmin,
        ),
        albums: updatedAlbums,
      );
    });
  }

  @override
  Future<void> clearUserData() async {
    await _commit((state) {
      return state.copyWith(
        media: [],
        albums: [],
        favorites: {},
        trash: [],
      );
    });
  }

  @override
  Future<void> resetToDemo() async {
    await _commit((state) {
      final seed = seedLibrary(clock());
      return seed.copyWith(
        profile: state.profile,
      );
    });
  }

  Future<void>? _inFlightSync;

  Future<void> syncWithServer({
    Uri? serverUri,
    String? token,
    HomeSpaceApiClient? apiClient,
    bool clearLocalFirst = false,
  }) {
    if (_inFlightSync != null) return _inFlightSync!;
    final future = _performSyncWithServer(
      serverUri: serverUri,
      token: token,
      apiClient: apiClient,
      clearLocalFirst: clearLocalFirst,
    ).whenComplete(() {
      _inFlightSync = null;
    });
    _inFlightSync = future;
    return future;
  }

  Future<void> _performSyncWithServer({
    Uri? serverUri,
    String? token,
    HomeSpaceApiClient? apiClient,
    bool clearLocalFirst = false,
  }) async {
    final activeUri = serverUri ?? getServerAddress?.call();
    final activeToken = token ?? getAuthToken?.call();
    if (activeUri == null || activeToken == null || activeToken.startsWith('local_')) return;

    final client = apiClient ?? _apiClient;
    try {
      // 1. Paginate all remote active media items
      final remoteItems = <MediaItem>[];
      final remoteFavorites = <String>{};
      var offset = 0;
      const pageSize = 200;
      var remoteMediaOk = false;

      while (true) {
        final page = await client.fetchMediaPage(
          baseUri: activeUri,
          token: activeToken,
          limit: pageSize,
          offset: offset,
        );
        remoteMediaOk = true;
        remoteItems.addAll(page.items);
        remoteFavorites.addAll(page.favoriteIds);
        if (page.items.length < pageSize || remoteItems.length >= page.total) {
          break;
        }
        offset += page.items.length;
      }

      // 2. Fetch remote trash
      var remoteTrashOk = false;
      final remoteTrashed = <MediaItem>[];
      try {
        remoteTrashed.addAll(
          await client.fetchTrash(baseUri: activeUri, token: activeToken),
        );
        remoteTrashOk = true;
      } catch (_) {}

      // 3. Fetch remote albums + shared media + optional family directory
      HomeSpaceAlbumsBundle? albumsBundle;
      var remoteAlbumsOk = false;
      try {
        albumsBundle = await client.fetchAlbumsBundle(
          baseUri: activeUri,
          token: activeToken,
          currentUserId: _data.profile.userId,
          includeMedia: true,
        );
        remoteAlbumsOk = true;
      } catch (_) {}

      final fetchedMembers = <FamilyMember>[];
      try {
        fetchedMembers.addAll(
          await client.fetchFamilyMembers(baseUri: activeUri, token: activeToken),
        );
      } catch (_) {}

      await _commit((state) {
        final baseMedia = clearLocalFirst ? <MediaItem>[] : state.media;
        final existingById = {for (final m in baseMedia) m.id: m};
        final existingByTitle = {
          for (final m in baseMedia) m.title.trim().toLowerCase(): m,
        };

        final remoteActiveIds = {for (final m in remoteItems) m.id};
        final remoteTrashIds = {for (final m in remoteTrashed) m.id};
        final sharedAlbumMedia = albumsBundle?.sharedMedia ?? const <MediaItem>[];
        final remoteSharedIds = {for (final m in sharedAlbumMedia) m.id};

        final updatedMedia = <MediaItem>[...baseMedia];
        var updatedFavorites = {...state.favorites};
        var updatedAlbums = clearLocalFirst ? <Album>[] : [...state.albums];
        var updatedTrash = clearLocalFirst ? <TrashEntry>[] : [...state.trash];

        // Remove stale synced items deleted on server when full active + trash lists succeeded
        if (remoteMediaOk && remoteTrashOk) {
          final stillOnServer = {
            ...remoteActiveIds,
            ...remoteTrashIds,
            ...remoteSharedIds,
          };
          final removedIds = updatedMedia
              .where((m) => m.isSynced && !stillOnServer.contains(m.id))
              .map((m) => m.id)
              .toSet();
          if (removedIds.isNotEmpty) {
            updatedMedia.removeWhere((m) => removedIds.contains(m.id));
            updatedFavorites.removeAll(removedIds);
            updatedTrash.removeWhere((t) => removedIds.contains(t.mediaId));
            existingById.removeWhere((k, _) => removedIds.contains(k));
            updatedAlbums = updatedAlbums.map((a) {
              final nextIds = a.mediaIds.where((id) => !removedIds.contains(id)).toList();
              final nextAddedBy = {...a.addedBy}..removeWhere((k, _) => removedIds.contains(k));
              final nextCover = a.coverId != null && nextIds.contains(a.coverId)
                  ? a.coverId
                  : nextIds.firstOrNull;
              return a.copyWith(
                mediaIds: nextIds,
                addedBy: nextAddedBy,
                coverId: nextCover,
                clearCover: nextIds.isEmpty,
              );
            }).toList();
          }
        }

        // Reconcile remote active media
        void mergeRemoteMedia(MediaItem remote) {
          final lowerTitle = remote.title.trim().toLowerCase();
          final byId = existingById[remote.id];
          if (byId != null) {
            final idx = updatedMedia.indexWhere((m) => m.id == remote.id);
            if (idx != -1) {
              final hasLocalAsset =
                  !byId.asset.startsWith('http') &&
                  !byId.asset.startsWith('assets/') &&
                  byId.asset.isNotEmpty;
              updatedMedia[idx] = byId.copyWith(
                isSynced: true,
                asset: hasLocalAsset ? byId.asset : remote.asset,
                sizeBytes: remote.sizeBytes ?? byId.sizeBytes,
                mimeType: remote.mimeType ?? byId.mimeType,
              );
            }
            return;
          }
          final byName = lowerTitle.isNotEmpty ? existingByTitle[lowerTitle] : null;
          if (byName != null) {
            final oldId = byName.id;
            final newId = remote.id;
            final idx = updatedMedia.indexWhere((m) => m.id == oldId);
            if (idx != -1) {
              updatedMedia[idx] = byName.copyWith(
                id: newId,
                isSynced: true,
                sizeBytes: remote.sizeBytes ?? byName.sizeBytes,
                mimeType: remote.mimeType ?? byName.mimeType,
              );
              existingById.remove(oldId);
              existingById[newId] = updatedMedia[idx];
              if (oldId != newId) {
                if (updatedFavorites.remove(oldId)) {
                  updatedFavorites.add(newId);
                }
                updatedAlbums = updatedAlbums.map((a) {
                  final nextMediaIds = a.mediaIds.map((id) => id == oldId ? newId : id).toList();
                  final nextCover = a.coverId == oldId ? newId : a.coverId;
                  final nextAddedBy = <String, String>{};
                  a.addedBy.forEach((key, val) {
                    nextAddedBy[key == oldId ? newId : key] = val;
                  });
                  return a.copyWith(mediaIds: nextMediaIds, coverId: nextCover, addedBy: nextAddedBy);
                }).toList();
                updatedTrash = updatedTrash.map((t) => t.mediaId == oldId ? TrashEntry(newId, t.deletedAt) : t).toList();
              }
            }
            return;
          }
          updatedMedia.add(remote);
          existingById[remote.id] = remote;
          if (lowerTitle.isNotEmpty) {
            existingByTitle[lowerTitle] = remote;
          }
        }

        for (final remote in remoteItems) {
          mergeRemoteMedia(remote);
        }
        for (final shared in sharedAlbumMedia) {
          mergeRemoteMedia(shared);
        }

        // Reconcile remote favorites cleanly for active server media
        if (remoteMediaOk) {
          updatedFavorites.removeWhere((id) => remoteActiveIds.contains(id) && !remoteFavorites.contains(id));
          final validMediaIds = {for (final m in updatedMedia) m.id};
          updatedFavorites.addAll(remoteFavorites.where(validMediaIds.contains));
        }

        // Reconcile remote trash
        if (remoteTrashOk) {
          final currentTrashMap = {for (final t in updatedTrash) t.mediaId: t};
          final now = clock().toUtc();
          for (final remote in remoteTrashed) {
            mergeRemoteMedia(remote);
            currentTrashMap.putIfAbsent(remote.id, () => TrashEntry(remote.id, now));
          }
          // Restore locally trashed synced items that are active on server again
          currentTrashMap.removeWhere((id, _) => remoteActiveIds.contains(id) && !remoteTrashIds.contains(id));
          updatedTrash = currentTrashMap.values.toList();
        }

        // Reconcile albums and family members referenced in albums
        final familyMap = {for (final f in state.family) f.id: f};
        for (final f in fetchedMembers) {
          familyMap[f.id] = f;
        }
        if (albumsBundle != null) {
          for (final f in albumsBundle.members) {
            familyMap[f.id] = f;
          }
          final finalMediaIds = {for (final m in updatedMedia) m.id};
          final remoteAlbums = albumsBundle.albums;
          for (final remote in remoteAlbums) {
            // Filter album mediaIds to media present in updatedMedia so SnapshotCodec.validate holds
            final validAlbumMedia = remote.mediaIds.where(finalMediaIds.contains).toList();
            final validAddedBy = <String, String>{};
            for (final mid in validAlbumMedia) {
              final adder = remote.addedBy[mid] ?? state.profile.userId;
              validAddedBy[mid] = adder;
              if (adder != state.profile.userId) {
                familyMap.putIfAbsent(adder, () => FamilyMember(adder, 'Family Member'));
              }
            }
            for (final mem in remote.memberships) {
              if (mem.userId != state.profile.userId) {
                familyMap.putIfAbsent(mem.userId, () => FamilyMember(mem.userId, 'Family Member'));
              }
            }
            final validCover = remote.coverId != null && validAlbumMedia.contains(remote.coverId)
                ? remote.coverId
                : validAlbumMedia.firstOrNull;
            final normalizedAlbum = remote.copyWith(
              mediaIds: validAlbumMedia,
              addedBy: validAddedBy,
              coverId: validCover,
              clearCover: validAlbumMedia.isEmpty,
            );

            final existingIdx = updatedAlbums.indexWhere((a) => a.id == normalizedAlbum.id);
            if (existingIdx != -1) {
              updatedAlbums[existingIdx] = normalizedAlbum;
            } else {
              updatedAlbums.add(normalizedAlbum);
            }
          }
          if (remoteAlbumsOk && remoteAlbums.isNotEmpty) {
            // Keep locally-created demo/offline albums only when not explicitly synced, or remove deleted server albums
            final remoteAlbumIds = {for (final a in remoteAlbums) a.id};
            updatedAlbums.removeWhere((a) =>
                a.id.startsWith('album-') &&
                a.roleFor(state.profile.userId) == AlbumRole.owner &&
                a.mediaIds.every((mid) => remoteActiveIds.contains(mid)) &&
                !remoteAlbumIds.contains(a.id));
          }
        }

        familyMap.remove(state.profile.userId);
        updatedMedia.sort(MediaItem.compareNewestFirst);

        return state.copyWith(
          media: updatedMedia,
          favorites: updatedFavorites,
          albums: updatedAlbums,
          trash: updatedTrash,
          family: familyMap.values.toList(),
        );
      });
    } catch (e) {
      debugPrint('syncWithServer error: $e');
    }
  }

  @override
  Future<void> toggleFavorite(String id) async {
    bool isNowFav = false;
    await _commit((state) {
      _requireMedia(state, id);
      if (state.trash.any((entry) => entry.mediaId == id)) {
        throw const LocalActionException('Restore this memory first.');
      }
      final next = {...state.favorites};
      if (next.contains(id)) {
        next.remove(id);
        isNowFav = false;
      } else {
        next.add(id);
        isNowFav = true;
      }
      return state.copyWith(favorites: next);
    });

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      unawaited(
        _apiClient.toggleFavorite(
          baseUri: activeUri,
          token: activeToken,
          mediaId: id,
          isFavorite: isNowFav,
        ).catchError((_) {}),
      );
    }
  }

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
  Future<void> setFavorites(List<String> ids, bool favorite) async {
    final requested = List<String>.of(ids);
    await _commit((state) {
      final active = _activeIds(state, requested);
      final next = {...state.favorites};
      favorite ? next.addAll(active) : next.removeAll(active);
      return state.copyWith(favorites: next);
    });

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null && !activeToken.startsWith('local_')) {
      unawaited(
        _apiClient.batchSetFavorites(
          baseUri: activeUri,
          token: activeToken,
          mediaIds: requested,
          isFavorite: favorite,
        ).catchError((e) => debugPrint('batchSetFavorites error: $e')),
      );
    }
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
  Future<void> setAppLock({required bool enabled, String? pin}) {
    final storedPin = (pin != null && pin.isNotEmpty && !PinSecurity.isHashed(pin))
        ? PinSecurity.hashPin(pin)
        : pin;
    return _commit(
      (state) => state.copyWith(
        profile: state.profile.copyWith(
          appLockEnabled: enabled,
          appLockPin: storedPin,
        ),
      ),
    );
  }

  @override
  Future<StorageBreakdown> getStorageBreakdown() async {
    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null && !activeToken.startsWith('local_')) {
      try {
        return await _apiClient.fetchStorageBreakdown(
          baseUri: activeUri,
          token: activeToken,
        );
      } catch (e) {
        debugPrint('fetchStorageBreakdown error: $e');
      }
    }
    var photoBytes = 0;
    var videoBytes = 0;
    for (final m in media) {
      int sz;
      if (m.sizeBytes != null && m.sizeBytes! > 0) {
        sz = m.sizeBytes!;
      } else if (m.asset.isNotEmpty &&
          !m.asset.startsWith('http') &&
          !m.asset.startsWith('assets/') &&
          File(m.asset).existsSync()) {
        sz = File(m.asset).lengthSync();
      } else {
        sz = m.kind == MediaKind.video ? 18 * 1024 * 1024 : 2 * 1024 * 1024;
      }
      if (m.kind == MediaKind.video) {
        videoBytes += sz;
      } else {
        photoBytes += sz;
      }
    }
    final totalUsed = photoBytes + videoBytes;
    const totalQuota = 15 * 1024 * 1024 * 1024;
    return StorageBreakdown(
      photosBytes: photoBytes,
      videosBytes: videoBytes,
      totalUsedBytes: totalUsed,
      quotaBytes: totalQuota,
    );
  }

  final List<FamilyAccount> _localFamilyAccounts = [
    const FamilyAccount(
      id: 'member-maya',
      email: 'maya@homespace.local',
      name: 'Maya',
      avatarTone: AvatarTone.orange,
      isAdmin: true,
      storageQuotaBytes: 15 * 1024 * 1024 * 1024,
      storageUsedBytes: 2 * 1024 * 1024 * 1024,
    ),
    const FamilyAccount(
      id: 'member-alex',
      email: 'alex@homespace.local',
      name: 'Alex',
      avatarTone: AvatarTone.blue,
      isAdmin: false,
      storageQuotaBytes: 15 * 1024 * 1024 * 1024,
      storageUsedBytes: 1024 * 1024 * 1024,
    ),
  ];

  @override
  Future<List<FamilyAccount>> getFamilyAccounts() async {
    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null && !activeToken.startsWith('local_')) {
      return await _apiClient.fetchAdminUsers(
        baseUri: activeUri,
        token: activeToken,
      );
    }
    return List.unmodifiable(_localFamilyAccounts);
  }

  @override
  Future<void> createFamilyMember({
    required String name,
    required String email,
    required String password,
    AvatarTone avatarTone = AvatarTone.orange,
    int storageQuotaBytes = 15 * 1024 * 1024 * 1024,
    bool isAdmin = false,
  }) async {
    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      await _apiClient.createAdminUser(
        baseUri: activeUri,
        token: activeToken,
        name: name,
        email: email,
        password: password,
        avatarTone: avatarTone.name,
        storageQuotaBytes: storageQuotaBytes,
        isAdmin: isAdmin,
      );
    }
    _localFamilyAccounts.add(FamilyAccount(
      id: 'u_${DateTime.now().millisecondsSinceEpoch}',
      email: email,
      name: name,
      avatarTone: avatarTone,
      isAdmin: isAdmin,
      storageQuotaBytes: storageQuotaBytes,
      storageUsedBytes: 0,
      createdAt: DateTime.now(),
    ));
    notifyListeners();
  }

  @override
  Future<void> deleteFamilyMember(String userId) async {
    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      await _apiClient.deleteAdminUser(
        baseUri: activeUri,
        token: activeToken,
        userId: userId,
      );
    }
    _localFamilyAccounts.removeWhere((acc) => acc.id == userId);
    notifyListeners();
  }

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

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      unawaited(() async {
        try {
          await _apiClient.createRemoteAlbum(
            baseUri: activeUri,
            token: activeToken,
            id: createdId,
            title: title,
            description: description.trim(),
            mediaIds: requested,
            coverMediaId: coverId ?? requested.firstOrNull,
            currentUserId: _data.profile.userId,
          );
        } catch (e) {
          debugPrint('Error syncing createAlbum: $e');
        }
      }());
    }

    return createdId!;
  }

  @override
  Future<void> renameAlbum(String id, String title) async {
    final clean = _name(title, 80);
    await _commit((state) {
      final album = _album(state, id);
      _owner(state, album);
      return _replace(state, album.copyWith(title: clean));
    });

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      unawaited(_apiClient.updateRemoteAlbum(
        baseUri: activeUri,
        token: activeToken,
        albumId: id,
        title: clean,
      ).catchError((e) => debugPrint('Error syncing renameAlbum: $e')));
    }
  }

  @override
  Future<void> updateAlbum(
    String id,
    String title,
    String description, {
    String? coverId,
  }) async {
    final cleanTitle = _name(title, 80);
    final cleanDesc = description.trim();
    await _commit((state) {
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
          title: cleanTitle,
          description: cleanDesc,
          coverId: coverId,
        ),
      );
    });

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      unawaited(_apiClient.updateRemoteAlbum(
        baseUri: activeUri,
        token: activeToken,
        albumId: id,
        title: cleanTitle,
        description: cleanDesc,
        coverMediaId: coverId,
      ).catchError((e) => debugPrint('Error syncing updateAlbum: $e')));
    }
  }

  @override
  Future<void> deleteAlbum(String id) async {
    await _commit((state) {
      _owner(state, _album(state, id));
      return state.copyWith(
        albums: state.albums.where((album) => album.id != id).toList(),
      );
    });

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      unawaited(_apiClient.deleteRemoteAlbum(
        baseUri: activeUri,
        token: activeToken,
        albumId: id,
      ).catchError((e) => debugPrint('Error syncing deleteAlbum: $e')));
    }
  }

  @override
  Future<void> setAlbumCover(String albumId, String mediaId) async {
    await _commit((state) {
      final album = _album(state, albumId);
      _owner(state, album);
      _activeIds(state, [mediaId]);
      if (!album.mediaIds.contains(mediaId)) {
        throw const LocalActionException('Add this memory to the album first.');
      }
      return _replace(state, album.copyWith(coverId: mediaId));
    });

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      unawaited(_apiClient.updateRemoteAlbum(
        baseUri: activeUri,
        token: activeToken,
        albumId: albumId,
        coverMediaId: mediaId,
      ).catchError((e) => debugPrint('Error syncing setAlbumCover: $e')));
    }
  }

  @override
  Future<void> addToAlbum(String albumId, String mediaId) =>
      addManyToAlbum(albumId, [mediaId]);

  @override
  Future<void> addManyToAlbum(String albumId, List<String> mediaIds) async {
    final requested = List<String>.of(mediaIds);
    await _commit((state) {
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

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      unawaited(_apiClient.addMediaToRemoteAlbum(
        baseUri: activeUri,
        token: activeToken,
        albumId: albumId,
        mediaIds: requested,
      ).catchError((e) => debugPrint('Error syncing addManyToAlbum: $e')));
    }
  }

  @override
  Future<void> removeFromAlbum(String albumId, String mediaId) =>
      removeManyFromAlbum(albumId, [mediaId]);

  @override
  Future<void> removeManyFromAlbum(String albumId, List<String> mediaIds) async {
    final requested = mediaIds.toSet();
    await _commit((state) {
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

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      unawaited(_apiClient.removeMediaFromRemoteAlbum(
        baseUri: activeUri,
        token: activeToken,
        albumId: albumId,
        mediaIds: mediaIds,
      ).catchError((e) => debugPrint('Error syncing removeManyFromAlbum: $e')));
    }
  }

  @override
  Future<void> setMemberRole(
    String albumId,
    String userId,
    AlbumRole role,
  ) async {
    List<AlbumMembership>? nextMemberships;
    await _commit((state) {
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
      nextMemberships = members;
      return _replace(state, album.copyWith(memberships: members));
    });

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null && !activeToken.startsWith('local_') && nextMemberships != null) {
      unawaited(
        _apiClient.updateAlbumMembers(
          baseUri: activeUri,
          token: activeToken,
          albumId: albumId,
          memberships: nextMemberships!,
        ).catchError((e) => debugPrint('Error syncing setMemberRole: $e')),
      );
    }
  }

  @override
  Future<void> removeMember(String albumId, String userId) async {
    List<AlbumMembership>? nextMemberships;
    await _commit((state) {
      final album = _album(state, albumId);
      _owner(state, album);
      if (album.roleFor(userId) == AlbumRole.owner) {
        throw const LocalActionException('The album owner cannot be removed.');
      }
      final members = album.memberships
          .where((member) => member.userId != userId)
          .toList();
      nextMemberships = members;
      return _replace(
        state,
        album.copyWith(memberships: members),
      );
    });

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null && !activeToken.startsWith('local_') && nextMemberships != null) {
      unawaited(
        _apiClient.updateAlbumMembers(
          baseUri: activeUri,
          token: activeToken,
          albumId: albumId,
          memberships: nextMemberships!,
        ).catchError((e) => debugPrint('Error syncing removeMember: $e')),
      );
    }
  }

  @override
  Future<void> moveToTrash(String id) => moveManyToTrash([id]);

  @override
  Future<void> moveManyToTrash(List<String> ids) async {
    final requested = ids.toSet();
    final targetedItems = _data.media.where((m) => requested.contains(m.id)).toList();
    final titles = targetedItems.map((m) => m.title).where((t) => t.isNotEmpty).toList();

    // Cancel any in-flight or queued uploads for these files
    final up = _uploads;
    for (final upload in up.items) {
      final uploadTitle = (upload.title ?? '').toLowerCase();
      if (titles.any((t) => t.toLowerCase() == uploadTitle)) {
        up.cancel(upload.id);
      }
    }

    // Register with AutoBackupService so both foreground and native background backup skip them
    unawaited(AutoBackupService.markMediaDeleted(titles));

    await _commit((state) {
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

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      unawaited(
        _apiClient.trashMedia(
          baseUri: activeUri,
          token: activeToken,
          mediaIds: ids,
          filenames: titles,
        ).catchError((e) {
          debugPrint('trashMedia failed: $e');
        }),
      );
    }
  }

  @override
  Future<void> restore(String id) => restoreMany([id]);

  @override
  Future<void> restoreMany(List<String> ids) async {
    final requested = ids.toSet();
    final targetedItems = _data.media.where((m) => requested.contains(m.id)).toList();
    final titles = targetedItems.map((m) => m.title).where((t) => t.isNotEmpty).toList();
    unawaited(AutoBackupService.unmarkMediaDeleted(titles));

    await _commit((state) {
      for (final id in requested) {
        _requireMedia(state, id);
      }
      return state.copyWith(
        trash: state.trash
            .where((entry) => !requested.contains(entry.mediaId))
            .toList(),
      );
    });

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      unawaited(
        _apiClient.restoreMedia(
          baseUri: activeUri,
          token: activeToken,
          mediaIds: ids,
          filenames: titles,
        ).catchError((e) {
          debugPrint('restoreMedia failed: $e');
        }),
      );
    }
  }

  @override
  Future<void> deletePermanently(String id) => deleteManyPermanently([id]);

  @override
  Future<void> deleteManyPermanently(List<String> ids) async {
    final requested = ids.toSet();
    final targetedItems = _data.media.where((m) => requested.contains(m.id)).toList();
    final titles = targetedItems.map((m) => m.title).where((t) => t.isNotEmpty).toList();

    // Cancel any in-flight or queued uploads for these files
    final up = _uploads;
    for (final upload in up.items) {
      final uploadTitle = (upload.title ?? '').toLowerCase();
      if (titles.any((t) => t.toLowerCase() == uploadTitle)) {
        up.cancel(upload.id);
      }
    }

    // Permanently record these signatures so auto-backup will never re-upload them from device
    unawaited(AutoBackupService.markMediaDeleted(titles));

    await _commit((state) {
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

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      try {
        await _apiClient.deleteMediaPermanently(
          baseUri: activeUri,
          token: activeToken,
          mediaIds: ids,
          filenames: titles,
        );
      } catch (e) {
        debugPrint('deleteMediaPermanently remote sync error: $e');
      }
    }
  }

  @override
  Future<void> emptyTrash() async {
    final trashEntries = List<TrashEntry>.from(_data.trash);
    if (trashEntries.isEmpty) return;

    final trashIds = trashEntries.map((e) => e.mediaId).toList();
    final targetedItems = _data.media.where((m) => trashIds.contains(m.id)).toList();
    final titles = targetedItems.map((m) => m.title).where((t) => t.isNotEmpty).toList();

    // Cancel any in-flight or queued uploads for these files
    final up = _uploads;
    for (final upload in up.items) {
      final uploadTitle = (upload.title ?? '').toLowerCase();
      if (titles.any((t) => t.toLowerCase() == uploadTitle)) {
        up.cancel(upload.id);
      }
    }

    // Permanently record these signatures so auto-backup will never re-upload them from device
    unawaited(AutoBackupService.markMediaDeleted(titles));

    final requested = trashIds.toSet();
    await _commit((state) {
      return state.copyWith(
        media: state.media
            .where((item) => !requested.contains(item.id))
            .toList(),
        favorites: {...state.favorites}..removeAll(requested),
        trash: const [],
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

    final activeUri = getServerAddress?.call();
    final activeToken = getAuthToken?.call();
    if (activeUri != null && activeToken != null) {
      try {
        await _apiClient.emptyTrash(
          baseUri: activeUri,
          token: activeToken,
          mediaIds: trashIds,
          filenames: titles,
        );
      } catch (e) {
        debugPrint('emptyTrash error: $e');
        try {
          await _apiClient.deleteMediaPermanently(
            baseUri: activeUri,
            token: activeToken,
            mediaIds: trashIds,
            filenames: titles,
          );
        } catch (_) {}
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsApiClient) {
      _apiClient.close();
    }
    final conn = _connection;
    if (conn is DemoConnectionRepository) {
      conn.dispose();
    }
    final up = _uploads;
    if (up is DemoUploadRepository) {
      up.dispose();
    }
    super.dispose();
  }
}
