enum Appearance { system, light, dark }

enum AvatarTone { orange, green, purple, blue }

enum MediaKind { photo, video }

enum AlbumRole { owner, contributor, viewer }

enum DemoScenario {
  populated,
  empty,
  loading,
  offline,
  failed,
  success;

  static DemoScenario parse(String value) =>
      values.firstWhere((item) => item.name == value, orElse: () => populated);
}

class MediaItem {
  final String id;
  final String asset;
  final String title;
  final String category;
  final DateTime takenAt;
  final MediaKind kind;
  const MediaItem({
    required this.id,
    required this.asset,
    required this.title,
    required this.category,
    required this.takenAt,
    this.kind = MediaKind.photo,
  });

  String dateLabel(DateTime now) {
    final local = takenAt.toLocal();
    final days = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(local.year, local.month, local.day)).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}

class FamilyMember {
  final String id;
  final String name;
  const FamilyMember(this.id, this.name);
  String get initial => name.trim().isEmpty
      ? '?'
      : String.fromCharCode(name.trim().runes.first).toUpperCase();
}

class AlbumMembership {
  final String userId;
  final AlbumRole role;
  const AlbumMembership(this.userId, this.role);
}

class Album {
  final String id;
  final String title;
  final String description;
  final List<String> mediaIds;
  final String? coverId;
  final List<AlbumMembership> memberships;
  final Map<String, String> addedBy;

  Album({
    required this.id,
    required this.title,
    required this.description,
    required List<String> mediaIds,
    required List<AlbumMembership> memberships,
    this.coverId,
    required Map<String, String> addedBy,
  }) : mediaIds = List.unmodifiable(mediaIds),
       memberships = List.unmodifiable(memberships),
       addedBy = Map.unmodifiable(addedBy);

  bool get shared => memberships.length > 1;
  AlbumRole? roleFor(String userId) {
    for (final membership in memberships) {
      if (membership.userId == userId) return membership.role;
    }
    return null;
  }

  Album copyWith({
    String? title,
    String? description,
    List<String>? mediaIds,
    List<AlbumMembership>? memberships,
    Map<String, String>? addedBy,
    String? coverId,
    bool clearCover = false,
  }) => Album(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    mediaIds: mediaIds ?? this.mediaIds,
    memberships: memberships ?? this.memberships,
    coverId: clearCover ? null : coverId ?? this.coverId,
    addedBy: addedBy ?? this.addedBy,
  );
}

class ProfileSettings {
  final String userId;
  final String name;
  final Appearance appearance;
  final AvatarTone avatarTone;
  const ProfileSettings({
    this.userId = 'member-maya',
    this.name = 'Maya',
    this.appearance = Appearance.system,
    this.avatarTone = AvatarTone.orange,
  });
  String get initial => FamilyMember(userId, name).initial;
  ProfileSettings copyWith({
    String? name,
    Appearance? appearance,
    AvatarTone? avatarTone,
  }) => ProfileSettings(
    userId: userId,
    name: name ?? this.name,
    appearance: appearance ?? this.appearance,
    avatarTone: avatarTone ?? this.avatarTone,
  );
}

class TrashEntry {
  final String mediaId;
  final DateTime deletedAt;
  const TrashEntry(this.mediaId, this.deletedAt);
}

class LibrarySnapshot {
  final List<MediaItem> media;
  final List<Album> albums;
  final Set<String> favorites;
  final List<TrashEntry> trash;
  final List<FamilyMember> family;
  final ProfileSettings profile;

  LibrarySnapshot({
    required List<MediaItem> media,
    required List<Album> albums,
    required Set<String> favorites,
    required List<TrashEntry> trash,
    required List<FamilyMember> family,
    required this.profile,
  }) : media = List.unmodifiable(media),
       albums = List.unmodifiable(albums),
       favorites = Set.unmodifiable(favorites),
       trash = List.unmodifiable(trash),
       family = List.unmodifiable(family);

  LibrarySnapshot copyWith({
    List<MediaItem>? media,
    List<Album>? albums,
    Set<String>? favorites,
    List<TrashEntry>? trash,
    List<FamilyMember>? family,
    ProfileSettings? profile,
  }) => LibrarySnapshot(
    media: media ?? this.media,
    albums: albums ?? this.albums,
    favorites: favorites ?? this.favorites,
    trash: trash ?? this.trash,
    family: family ?? this.family,
    profile: profile ?? this.profile,
  );
}

enum ConnectionPhase { disconnected, connecting, connected, offline, failed }

class ConnectionStatus {
  final ConnectionPhase phase;
  final Uri? address;
  final String message;
  final bool isDemo;
  const ConnectionStatus(
    this.phase,
    this.message, {
    this.address,
    this.isDemo = true,
  });
}

enum UploadPhase { queued, uploading, paused, failed, completed, canceled }

class UploadItem {
  final String id;
  final String mediaId;
  final int bytesSent;
  final int totalBytes;
  final UploadPhase phase;
  const UploadItem({
    required this.id,
    required this.mediaId,
    required this.totalBytes,
    this.bytesSent = 0,
    this.phase = UploadPhase.queued,
  });
  double get progress => totalBytes == 0 ? 0 : bytesSent / totalBytes;
  UploadItem copyWith({int? bytesSent, UploadPhase? phase}) => UploadItem(
    id: id,
    mediaId: mediaId,
    totalBytes: totalBytes,
    bytesSent: bytesSent ?? this.bytesSent,
    phase: phase ?? this.phase,
  );
}
