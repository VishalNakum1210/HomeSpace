class SamplePhoto {
  final int id;
  final int assetNumber;
  final String title;
  final String group;
  final String category;
  const SamplePhoto(
    this.id,
    this.assetNumber,
    this.title,
    this.group,
    this.category,
  );
  String get asset =>
      'assets/photos/photo_${assetNumber.toString().padLeft(2, '0')}.jpg';
}

const samplePhotos = [
  SamplePhoto(1, 1, 'Our kind of weekend', 'Today', 'People'),
  SamplePhoto(2, 2, 'A quiet afternoon by the lake', 'Today', 'Places'),
  SamplePhoto(3, 3, 'Taking the scenic route', 'Today', 'Places'),
  SamplePhoto(4, 4, 'Golden-hour smiles', 'Today', 'People'),
  SamplePhoto(5, 5, 'A little sea air', 'Today', 'Places'),
  SamplePhoto(6, 6, 'Under the stars', 'Today', 'Places'),
  SamplePhoto(7, 7, 'Slow mornings', 'Yesterday', 'Places'),
  SamplePhoto(8, 8, 'Better together', 'Yesterday', 'People'),
  SamplePhoto(9, 2, 'Somewhere we love', 'Yesterday', 'Places'),
  SamplePhoto(10, 1, 'The whole family', 'Yesterday', 'People'),
  SamplePhoto(11, 6, 'One more adventure', 'Yesterday', 'Places'),
  SamplePhoto(12, 5, 'See you at the beach', 'Yesterday', 'Places'),
];

class SampleAlbum {
  final String title;
  final String subtitle;
  final List<int> photos;
  final List<String> members;
  final bool shared;
  const SampleAlbum(
    this.title,
    this.subtitle,
    this.photos,
    this.members, {
    this.shared = false,
  });
  SamplePhoto get cover => samplePhotos[photos.first - 1];
}

const sampleAlbums = [
  SampleAlbum(
    'Family weekends',
    'Made for our favorite people',
    [1, 8, 10, 4],
    ['M', 'A', 'S'],
    shared: true,
  ),
  SampleAlbum(
    'Little adventures',
    'The places we keep coming back to',
    [3, 6, 7, 11],
    ['M', 'A'],
    shared: true,
  ),
  SampleAlbum(
    'By the water',
    'A little sunshine, a lot of memories',
    [2, 5, 9, 12],
    ['M'],
  ),
  SampleAlbum(
    'Everyday magic',
    'The small things are the big things',
    [4, 1, 8],
    ['M'],
  ),
];
