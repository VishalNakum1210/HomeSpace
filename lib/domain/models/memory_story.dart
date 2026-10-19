import 'media_item.dart';

class MemoryStory {
  final String id;
  final String title;
  final String subtitle;
  final String coverUrl;
  final List<MediaItem> items;
  final bool isViewed;

  const MemoryStory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.items,
    this.isViewed = false,
  });

  MemoryStory copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? coverUrl,
    List<MediaItem>? items,
    bool? isViewed,
  }) {
    return MemoryStory(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      coverUrl: coverUrl ?? this.coverUrl,
      items: items ?? this.items,
      isViewed: isViewed ?? this.isViewed,
    );
  }
}
