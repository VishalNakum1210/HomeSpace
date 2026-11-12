import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/domain/media_timeline.dart';
import 'package:homespace/domain/models.dart';

void main() {
  test(
    'Timeline groups keep descending dates and deterministic tied-photo order',
    () {
      final today = DateTime(2026, 10, 30);
      MediaItem photo(String id, DateTime date) => MediaItem(
        id: id,
        asset: 'unused.jpg',
        title: id,
        category: 'Family',
        takenAt: date,
      );
      final photos = [
        photo('yesterday', DateTime(2026, 10, 29)),
        photo('b', today),
        photo('a', today),
      ]..sort(MediaItem.compareNewestFirst);
      var calls = 0;
      final groups = groupMediaTimeline(photos, (item) {
        calls++;
        return item.dateLabel(today);
      });
      expect(groups.keys, ['Today', 'Yesterday']);
      expect(groups['Today']!.map((item) => item.id), ['a', 'b']);
      expect(groups['Yesterday']!.single.id, 'yesterday');
      expect(calls, photos.length);
      expect(groupMediaTimeline([], (_) => 'unused'), isEmpty);
    },
  );
}
