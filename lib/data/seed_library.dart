import '../domain/models.dart';

LibrarySnapshot seedLibrary(DateTime now) {
  final today = DateTime(now.year, now.month, now.day, 12);
  const descriptions = [
    (1, 'Our kind of weekend', 'People'),
    (2, 'A quiet afternoon by the lake', 'Places'),
    (3, 'Taking the scenic route', 'Places'),
    (4, 'Golden-hour smiles', 'People'),
    (5, 'A little sea air', 'Places'),
    (6, 'Under the stars', 'Places'),
    (7, 'Slow mornings', 'Places'),
    (8, 'Better together', 'People'),
    (2, 'Somewhere we love', 'Places'),
    (1, 'The whole family', 'People'),
    (6, 'One more adventure', 'Places'),
    (5, 'See you at the beach', 'Places'),
  ];
  String mediaId(int number) => 'media-${number.toString().padLeft(2, '0')}';
  Album album(
    String id,
    String title,
    String description,
    List<int> photos,
    List<AlbumMembership> members,
  ) => Album(
    id: id,
    title: title,
    description: description,
    mediaIds: photos.map(mediaId).toList(),
    coverId: mediaId(photos.first),
    memberships: members,
    addedBy: {
      for (final photo in photos)
        mediaId(photo): members
            .firstWhere((member) => member.role == AlbumRole.owner)
            .userId,
    },
  );
  return LibrarySnapshot(
    media: [
      for (var index = 0; index < descriptions.length; index++)
        MediaItem(
          id: mediaId(index + 1),
          asset:
              'assets/photos/photo_${descriptions[index].$1.toString().padLeft(2, '0')}.jpg',
          title: descriptions[index].$2,
          category: descriptions[index].$3,
          takenAt: today.subtract(Duration(days: index < 6 ? 0 : 1)).toUtc(),
        ),
    ],
    albums: [
      album(
        'album-family',
        'Family weekends',
        'Made for our favorite people',
        [1, 8, 10, 4],
        [
          const AlbumMembership('member-maya', AlbumRole.owner),
          const AlbumMembership('member-alex', AlbumRole.contributor),
          const AlbumMembership('member-sam', AlbumRole.viewer),
        ],
      ),
      album(
        'album-adventures',
        'Little adventures',
        'The places we keep coming back to',
        [3, 6, 7, 11],
        [
          const AlbumMembership('member-maya', AlbumRole.contributor),
          const AlbumMembership('member-alex', AlbumRole.owner),
        ],
      ),
      album(
        'album-water',
        'By the water',
        'A little sunshine, a lot of memories',
        [2, 5, 9, 12],
        [const AlbumMembership('member-maya', AlbumRole.owner)],
      ),
      album(
        'album-everyday',
        'Everyday magic',
        'The small things are the big things',
        [4, 1, 8],
        [const AlbumMembership('member-maya', AlbumRole.owner)],
      ),
    ],
    favorites: {mediaId(1), mediaId(2), mediaId(6)},
    trash: [],
    family: const [
      FamilyMember('member-alex', 'Alex'),
      FamilyMember('member-sam', 'Sam'),
    ],
    profile: const ProfileSettings(),
  );
}
