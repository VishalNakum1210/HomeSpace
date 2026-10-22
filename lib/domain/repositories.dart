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
  Future<void> moveToTrash(String id);
  Future<void> restore(String id);
  Future<void> deletePermanently(String id);
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
  });
  Future<void> renameAlbum(String id, String title);
  Future<void> addToAlbum(String albumId, String mediaId);
  Future<void> removeFromAlbum(String albumId, String mediaId);
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
