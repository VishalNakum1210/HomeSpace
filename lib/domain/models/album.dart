class Album {
  final String id;
  final String title;
  final String coverUrl;
  final int itemCount;
  final bool isShared;
  final List<String> sharedUserAvatars;
  final List<String> mediaIds;
  final DateTime createdAt;

  const Album({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.itemCount,
    this.isShared = false,
    this.sharedUserAvatars = const [],
    this.mediaIds = const [],
    required this.createdAt,
  });

  Album copyWith({
    String? id,
    String? title,
    String? coverUrl,
    int? itemCount,
    bool? isShared,
    List<String>? sharedUserAvatars,
    List<String>? mediaIds,
    DateTime? createdAt,
  }) {
    return Album(
      id: id ?? this.id,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      itemCount: itemCount ?? this.itemCount,
      isShared: isShared ?? this.isShared,
      sharedUserAvatars: sharedUserAvatars ?? this.sharedUserAvatars,
      mediaIds: mediaIds ?? this.mediaIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class DeviceFolder {
  final String id;
  final String name;
  final String coverUrl;
  final int itemCount;
  final bool isBackedUp;

  const DeviceFolder({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.itemCount,
    this.isBackedUp = true,
  });

  DeviceFolder copyWith({
    String? id,
    String? name,
    String? coverUrl,
    int? itemCount,
    bool? isBackedUp,
  }) {
    return DeviceFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      coverUrl: coverUrl ?? this.coverUrl,
      itemCount: itemCount ?? this.itemCount,
      isBackedUp: isBackedUp ?? this.isBackedUp,
    );
  }
}
