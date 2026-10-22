import 'dart:convert';

import '../domain/models.dart';

class UnsupportedSnapshotVersion implements Exception {
  final int version;
  const UnsupportedSnapshotVersion(this.version);
  @override
  String toString() =>
      'This library was saved by a newer HomeSpace version ($version). Update the app to open it.';
}

class SnapshotCodec {
  static const version = 1;

  static String encode(LibrarySnapshot data) => jsonEncode({
    'schemaVersion': version,
    'media': [
      for (final item in data.media)
        {
          'id': item.id,
          'asset': item.asset,
          'title': item.title,
          'category': item.category,
          'takenAt': item.takenAt.toUtc().toIso8601String(),
          'kind': item.kind.name,
        },
    ],
    'albums': [
      for (final album in data.albums)
        {
          'id': album.id,
          'title': album.title,
          'description': album.description,
          'mediaIds': album.mediaIds,
          'coverId': album.coverId,
          'addedBy': album.addedBy,
          'memberships': [
            for (final member in album.memberships)
              {'userId': member.userId, 'role': member.role.name},
          ],
        },
    ],
    'favorites': data.favorites.toList(),
    'trash': [
      for (final item in data.trash)
        {
          'mediaId': item.mediaId,
          'deletedAt': item.deletedAt.toUtc().toIso8601String(),
        },
    ],
    'family': [
      for (final member in data.family) {'id': member.id, 'name': member.name},
    ],
    'profile': {
      'userId': data.profile.userId,
      'name': data.profile.name,
      'appearance': data.profile.appearance.name,
      'avatarTone': data.profile.avatarTone.name,
    },
  });

  static LibrarySnapshot decode(String input) {
    final root = _object(jsonDecode(input));
    final schema = root['schemaVersion'];
    if (schema is! int) throw const FormatException('Missing library version.');
    if (schema > version) throw UnsupportedSnapshotVersion(schema);
    if (schema != version) {
      throw const FormatException('Unsupported old library format.');
    }
    final profile = _object(root['profile']);
    final data = LibrarySnapshot(
      media: [for (final raw in _list(root['media'])) _media(_object(raw))],
      albums: [for (final raw in _list(root['albums'])) _album(_object(raw))],
      favorites: _strings(root['favorites']).toSet(),
      trash: [for (final raw in _list(root['trash'])) _trash(_object(raw))],
      family: [for (final raw in _list(root['family'])) _member(_object(raw))],
      profile: ProfileSettings(
        userId: _text(profile['userId']),
        name: _text(profile['name']),
        appearance: _enum(Appearance.values, profile['appearance']),
        avatarTone: _enum(AvatarTone.values, profile['avatarTone']),
      ),
    );
    validate(data);
    return data;
  }

  static void validate(LibrarySnapshot data) {
    final mediaIds = _unique(data.media.map((item) => item.id));
    _unique(data.albums.map((item) => item.id));
    _unique(data.trash.map((item) => item.mediaId));
    final userIds = _unique([
      data.profile.userId,
      ...data.family.map((item) => item.id),
    ]);
    for (final id in [
      ...data.favorites,
      ...data.trash.map((entry) => entry.mediaId),
    ]) {
      if (!mediaIds.contains(id)) {
        throw const FormatException('Unknown media reference.');
      }
    }
    for (final album in data.albums) {
      _unique(album.mediaIds);
      _unique(album.memberships.map((item) => item.userId));
      if (album.memberships
              .where((item) => item.role == AlbumRole.owner)
              .length !=
          1) {
        throw const FormatException('An album must have exactly one owner.');
      }
      if (album.roleFor(data.profile.userId) == null) {
        throw const FormatException('Album access is missing.');
      }
      for (final id in album.mediaIds) {
        if (!mediaIds.contains(id)) {
          throw const FormatException('Unknown album media.');
        }
        if (!userIds.contains(album.addedBy[id])) {
          throw const FormatException('Missing contributor attribution.');
        }
      }
      if (album.addedBy.keys.any((id) => !album.mediaIds.contains(id))) {
        throw const FormatException('Unknown contribution reference.');
      }
      for (final member in album.memberships) {
        if (!userIds.contains(member.userId)) {
          throw const FormatException('Unknown album member.');
        }
      }
      if (album.coverId != null && !album.mediaIds.contains(album.coverId)) {
        throw const FormatException('Album cover is not in the album.');
      }
    }
  }

  static MediaItem _media(Map<String, Object?> value) => MediaItem(
    id: _text(value['id']),
    asset: _text(value['asset']),
    title: _text(value['title']),
    category: _text(value['category']),
    takenAt: _date(value['takenAt']),
    kind: _enum(MediaKind.values, value['kind']),
  );
  static Album _album(Map<String, Object?> value) => Album(
    id: _text(value['id']),
    title: _text(value['title']),
    description: _text(value['description'], allowEmpty: true),
    mediaIds: _strings(value['mediaIds']),
    coverId: value['coverId'] == null ? null : _text(value['coverId']),
    addedBy: _object(value['addedBy'])
        .map((key, value) => MapEntry(key, _text(value))),
    memberships: [
      for (final raw in _list(value['memberships'])) _membership(_object(raw)),
    ],
  );
  static AlbumMembership _membership(Map<String, Object?> value) =>
      AlbumMembership(
        _text(value['userId']),
        _enum(AlbumRole.values, value['role']),
      );
  static TrashEntry _trash(Map<String, Object?> value) =>
      TrashEntry(_text(value['mediaId']), _date(value['deletedAt']));
  static FamilyMember _member(Map<String, Object?> value) =>
      FamilyMember(_text(value['id']), _text(value['name']));

  static Map<String, Object?> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected an object.');
    }
    return value;
  }

  static List<Object?> _list(Object? value) {
    if (value is! List) throw const FormatException('Expected a list.');
    return value.cast<Object?>();
  }

  static List<String> _strings(Object? value) => [
    for (final raw in _list(value)) _text(raw),
  ];
  static String _text(Object? value, {bool allowEmpty = false}) {
    if (value is! String ||
        (!allowEmpty && value.trim().isEmpty) ||
        value.length > 4096) {
      throw const FormatException('Invalid text value.');
    }
    return value;
  }

  static DateTime _date(Object? value) {
    final parsed = DateTime.tryParse(_text(value));
    if (parsed == null) throw const FormatException('Invalid date.');
    return parsed;
  }

  static T _enum<T extends Enum>(List<T> values, Object? value) =>
      values.firstWhere(
        (item) => item.name == value,
        orElse: () => throw const FormatException('Invalid enum value.'),
      );
  static Set<String> _unique(Iterable<String> ids) {
    final result = <String>{};
    for (final id in ids) {
      if (id.trim().isEmpty || !result.add(id)) {
        throw const FormatException('Duplicate or empty ID.');
      }
    }
    return result;
  }
}
