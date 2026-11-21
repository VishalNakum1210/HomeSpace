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

/// Parses date and time from standard camera/screenshot filenames (e.g. IMG_20261113_180034.jpg, VID_20261113_180034.mp4).
DateTime? parseDateFromFileName(String filename) {
  final match = RegExp(r'(\d{4})(\d{2})(\d{2})[_-](\d{2})(\d{2})(\d{2})').firstMatch(filename);
  if (match != null) {
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    final hour = int.tryParse(match.group(4)!);
    final minute = int.tryParse(match.group(5)!);
    final second = int.tryParse(match.group(6)!);
    if (year != null && month != null && day != null && hour != null && minute != null && second != null) {
      if (year >= 1970 && year <= 2100 && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day, hour, minute, second);
      }
    }
  }

  final dateOnly = RegExp(r'(?:IMG_|VID_|PXL_|Screenshot_)?(\d{4})[-_]?(\d{2})[-_]?(\d{2})', caseSensitive: false).firstMatch(filename);
  if (dateOnly != null) {
    final year = int.tryParse(dateOnly.group(1)!);
    final month = int.tryParse(dateOnly.group(2)!);
    final day = int.tryParse(dateOnly.group(3)!);
    if (year != null && month != null && day != null && year >= 1970 && year <= 2100 && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return DateTime(year, month, day, 12, 0, 0);
    }
  }
  return null;
}

class MediaItem {
  /// Stable ordering shared by the library and album timelines.
  static int compareNewestFirst(MediaItem a, MediaItem b) {
    final date = b.takenAt.compareTo(a.takenAt);
    return date == 0 ? a.id.compareTo(b.id) : date;
  }

  final String id;
  final String asset;
  final String title;
  final String category;
  final DateTime takenAt;
  final MediaKind kind;
  final Duration? duration;
  final bool isSynced;
  const MediaItem({
    required this.id,
    required this.asset,
    required this.title,
    required this.category,
    required this.takenAt,
    this.kind = MediaKind.photo,
    this.duration,
    this.isSynced = false,
  });

  MediaItem copyWith({
    String? id,
    String? asset,
    String? title,
    String? category,
    DateTime? takenAt,
    MediaKind? kind,
    Duration? duration,
    bool? isSynced,
  }) => MediaItem(
    id: id ?? this.id,
    asset: asset ?? this.asset,
    title: title ?? this.title,
    category: category ?? this.category,
    takenAt: takenAt ?? this.takenAt,
    kind: kind ?? this.kind,
    duration: duration ?? this.duration,
    isSynced: isSynced ?? this.isSynced,
  );

  String? get formattedDuration {
    if (duration == null) return null;
    final totalSeconds = duration!.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

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
    String? userId,
    String? name,
    Appearance? appearance,
    AvatarTone? avatarTone,
  }) => ProfileSettings(
    userId: userId ?? this.userId,
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
  final String? title;
  final int bytesSent;
  final int totalBytes;
  final UploadPhase phase;
  const UploadItem({
    required this.id,
    required this.mediaId,
    this.title,
    required this.totalBytes,
    this.bytesSent = 0,
    this.phase = UploadPhase.queued,
  });
  double get progress {
    if (totalBytes == 0) return 0;
    if (phase == UploadPhase.completed) return 1.0;
    return (bytesSent / totalBytes).clamp(0.0, 1.0);
  }
  UploadItem copyWith({
    String? title,
    int? bytesSent,
    int? totalBytes,
    UploadPhase? phase,
  }) => UploadItem(
    id: id,
    mediaId: mediaId,
    title: title ?? this.title,
    totalBytes: totalBytes ?? this.totalBytes,
    bytesSent: bytesSent ?? this.bytesSent,
    phase: phase ?? this.phase,
  );
}
