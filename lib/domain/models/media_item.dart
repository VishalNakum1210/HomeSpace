class MediaItem {
  final String id;
  final String title;
  final String url;
  final String thumbnailUrl;
  final DateTime dateTime;
  final String location;
  final double latitude;
  final double longitude;
  final bool isFavorite;
  final bool isArchived;
  final bool isTrash;
  final bool isVideo;
  final String? duration;
  final String fileSize;
  final String resolution;
  final String cameraInfo;
  final List<String> tags;
  final List<String> people;
  final int dominantColorValue;
  final double brightnessAdjustment;
  final double contrastAdjustment;
  final double saturationAdjustment;
  final String filterName;
  final bool isMotionPhoto;

  const MediaItem({
    required this.id,
    required this.title,
    required this.url,
    required this.thumbnailUrl,
    required this.dateTime,
    required this.location,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.isFavorite = false,
    this.isArchived = false,
    this.isTrash = false,
    this.isVideo = false,
    this.duration,
    required this.fileSize,
    required this.resolution,
    required this.cameraInfo,
    this.tags = const [],
    this.people = const [],
    this.dominantColorValue = 0xFF4285F4,
    this.brightnessAdjustment = 0.0,
    this.contrastAdjustment = 1.0,
    this.saturationAdjustment = 1.0,
    this.filterName = 'Original',
    this.isMotionPhoto = false,
  });

  MediaItem copyWith({
    String? id,
    String? title,
    String? url,
    String? thumbnailUrl,
    DateTime? dateTime,
    String? location,
    double? latitude,
    double? longitude,
    bool? isFavorite,
    bool? isArchived,
    bool? isTrash,
    bool? isVideo,
    String? duration,
    String? fileSize,
    String? resolution,
    String? cameraInfo,
    List<String>? tags,
    List<String>? people,
    int? dominantColorValue,
    double? brightnessAdjustment,
    double? contrastAdjustment,
    double? saturationAdjustment,
    String? filterName,
    bool? isMotionPhoto,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      dateTime: dateTime ?? this.dateTime,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
      isTrash: isTrash ?? this.isTrash,
      isVideo: isVideo ?? this.isVideo,
      duration: duration ?? this.duration,
      fileSize: fileSize ?? this.fileSize,
      resolution: resolution ?? this.resolution,
      cameraInfo: cameraInfo ?? this.cameraInfo,
      tags: tags ?? this.tags,
      people: people ?? this.people,
      dominantColorValue: dominantColorValue ?? this.dominantColorValue,
      brightnessAdjustment: brightnessAdjustment ?? this.brightnessAdjustment,
      contrastAdjustment: contrastAdjustment ?? this.contrastAdjustment,
      saturationAdjustment: saturationAdjustment ?? this.saturationAdjustment,
      filterName: filterName ?? this.filterName,
      isMotionPhoto: isMotionPhoto ?? this.isMotionPhoto,
    );
  }
}
