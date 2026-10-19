import 'package:myspace/domain/models/media_item.dart';
import 'package:myspace/domain/models/memory_story.dart';
import 'package:myspace/domain/models/album.dart';
import 'package:myspace/domain/models/user_account.dart';
import 'package:myspace/data/datasources/mock_media_data_source.dart';

class MediaRepository {
  List<MediaItem> _items = [];
  List<MemoryStory> _memories = [];
  List<Album> _albums = [];
  List<DeviceFolder> _deviceFolders = [];
  UserAccount _userAccount = MockMediaDataSource.getInitialUserAccount();

  MediaRepository() {
    _items = MockMediaDataSource.getInitialMediaItems();
    _memories = MockMediaDataSource.getInitialMemories(_items);
    _albums = MockMediaDataSource.getInitialAlbums(_items);
    _deviceFolders = MockMediaDataSource.getInitialDeviceFolders();
  }

  List<MediaItem> getActiveMediaItems() {
    return _items.where((i) => !i.isTrash && !i.isArchived).toList();
  }

  List<MediaItem> getFavoriteItems() {
    return _items.where((i) => i.isFavorite && !i.isTrash).toList();
  }

  List<MediaItem> getArchivedItems() {
    return _items.where((i) => i.isArchived && !i.isTrash).toList();
  }

  List<MediaItem> getTrashItems() {
    return _items.where((i) => i.isTrash).toList();
  }

  List<MemoryStory> getMemories() => List.unmodifiable(_memories);
  List<Album> getAlbums() => List.unmodifiable(_albums);
  List<DeviceFolder> getDeviceFolders() => List.unmodifiable(_deviceFolders);
  UserAccount getUserAccount() => _userAccount;

  MediaItem? getItemById(String id) {
    try {
      return _items.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  void toggleFavorite(String id) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1) {
      final current = _items[index];
      _items[index] = current.copyWith(isFavorite: !current.isFavorite);
    }
  }

  void moveToTrash(String id) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1) {
      _items[index] = _items[index].copyWith(isTrash: true);
    }
  }

  void restoreFromTrash(String id) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1) {
      _items[index] = _items[index].copyWith(isTrash: false);
    }
  }

  void deletePermanently(String id) {
    _items.removeWhere((i) => i.id == id);
  }

  void emptyTrash() {
    _items.removeWhere((i) => i.isTrash);
  }

  void toggleArchive(String id) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1) {
      final current = _items[index];
      _items[index] = current.copyWith(isArchived: !current.isArchived);
    }
  }

  void updatePhotoAdjustments({
    required String id,
    double? brightness,
    double? contrast,
    double? saturation,
    String? filterName,
  }) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1) {
      _items[index] = _items[index].copyWith(
        brightnessAdjustment: brightness ?? _items[index].brightnessAdjustment,
        contrastAdjustment: contrast ?? _items[index].contrastAdjustment,
        saturationAdjustment: saturation ?? _items[index].saturationAdjustment,
        filterName: filterName ?? _items[index].filterName,
      );
    }
  }

  void markMemoryAsViewed(String memoryId) {
    final index = _memories.indexWhere((m) => m.id == memoryId);
    if (index != -1) {
      _memories[index] = _memories[index].copyWith(isViewed: true);
    }
  }

  Album createAlbum(String title, List<String> mediaIds) {
    final coverUrl = mediaIds.isNotEmpty
        ? (_items.firstWhere((i) => i.id == mediaIds.first, orElse: () => _items.first).thumbnailUrl)
        : 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=600&q=80';

    final newAlbum = Album(
      id: 'album_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      coverUrl: coverUrl,
      itemCount: mediaIds.length,
      mediaIds: mediaIds,
      createdAt: DateTime.now(),
    );

    _albums.insert(0, newAlbum);
    return newAlbum;
  }

  void addItemsToAlbum(String albumId, List<String> mediaIds) {
    final index = _albums.indexWhere((a) => a.id == albumId);
    if (index != -1) {
      final current = _albums[index];
      final combined = {...current.mediaIds, ...mediaIds}.toList();
      _albums[index] = current.copyWith(
        mediaIds: combined,
        itemCount: combined.length,
      );
    }
  }

  void toggleBackup() {
    _userAccount = _userAccount.copyWith(
      isBackupEnabled: !_userAccount.isBackupEnabled,
      backupStatusText: !_userAccount.isBackupEnabled ? 'Backup complete' : 'Backup paused',
    );
  }

  void freeUpSpace(double freedGB) {
    final newUsed = (_userAccount.storageUsedGB - freedGB).clamp(0.0, _userAccount.storageTotalGB);
    _userAccount = _userAccount.copyWith(storageUsedGB: newUsed);
  }
}
