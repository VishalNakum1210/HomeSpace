import 'models.dart';

/// Groups an already ordered timeline without repeatedly filtering each grid
/// item. Map insertion order preserves the caller's date and photo ordering.
Map<String, List<MediaItem>> groupMediaTimeline(
  Iterable<MediaItem> media,
  String Function(MediaItem) labelFor,
) {
  final groups = <String, List<MediaItem>>{};
  for (final item in media) {
    (groups[labelFor(item)] ??= []).add(item);
  }
  return groups;
}
