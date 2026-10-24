import 'package:flutter/foundation.dart';

import 'models.dart';

class LocalActionException implements Exception {
  final String message;
  const LocalActionException(this.message);
  @override
  String toString() => message;
}

abstract interface class LibraryRepository {
  List<MediaItem> get media;
  Set<String> get favorites;
  List<TrashEntry> get trash;
  MediaItem? mediaById(String id);
  Future<void> toggleFavorite(String id);
  Future<void> setFavorites(List<String> ids, bool favorite);
  Future<void> moveToTrash(String id);
  Future<void> moveManyToTrash(List<String> ids);
  Future<void> restore(String id);
  Future<void> restoreMany(List<String> ids);
  Future<void> deletePermanently(String id);
  Future<void> deleteManyPermanently(List<String> ids);
}

abstract interface class AlbumRepository {
  List<Album> get albums;
  List<MediaItem> photosFor(Album album);
  MediaItem? coverFor(Album album);
  FamilyMember memberById(String id);
  Future<String> createAlbum(
    String title, {
    String description = '',
    List<String> mediaIds = const [],
    String? coverId,
  });
  Future<void> renameAlbum(String id, String title);
  Future<void> updateAlbum(
    String id,
    String title,
    String description, {
    String? coverId,
  });
  Future<void> deleteAlbum(String id);
  Future<void> setAlbumCover(String albumId, String mediaId);
  Future<void> addToAlbum(String albumId, String mediaId);
  Future<void> addManyToAlbum(String albumId, List<String> mediaIds);
  Future<void> removeFromAlbum(String albumId, String mediaId);
  Future<void> removeManyFromAlbum(String albumId, List<String> mediaIds);
  Future<void> setMemberRole(String albumId, String userId, AlbumRole role);
  Future<void> removeMember(String albumId, String userId);
}

abstract interface class ProfileRepository {
  ProfileSettings get profile;
  Future<void> setAppearance(Appearance appearance);
  Future<void> updateProfile(String name, AvatarTone tone);
}

abstract class HomeRepository extends ChangeNotifier
    implements LibraryRepository, AlbumRepository, ProfileRepository {
  bool get ready;
  String? get bootError;
  String? get recoveryNotice;
  int get pendingWrites;
  DemoScenario get scenario;
  LibrarySnapshot get snapshot;
  ConnectionRepository get connection;
  UploadRepository get uploads;
  Future<void> initialize();
  void setScenario(DemoScenario scenario);
  String groupFor(MediaItem item);
}

abstract interface class ConnectionRepository implements Listenable {
  ConnectionStatus get status;
  Future<ConnectionStatus> connect(Uri address);
  void disconnect();
}

abstract interface class UploadRepository implements Listenable {
  List<UploadItem> get items;
  void pause(String id);
  void resume(String id);
  void retry(String id);
  void cancel(String id);
}
