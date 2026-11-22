import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/design/space_widgets.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/library_widgets.dart';

Finder key(String value) => find.byKey(ValueKey(value));

Future<LocalHomeRepository> startSearchApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = LocalHomeRepository(
    store: MemorySnapshotStore(),
    initialAppearance: Appearance.light,
  );
  addTearDown(repository.dispose);

  await tester.pumpWidget(
    HomeSpaceApp(repository: repository),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await (FontLoader('Nunito')
          ..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  group('Phase 8: Search & Filters (Instant Local Querying & Timeline Jumping)', () {
    testWidgets('One-tap filter chips filter photos accurately', (tester) async {
      final repository = await startSearchApp(tester);
      final totalCount = repository.media.length;
      expect(totalCount, greaterThan(0));

      // 1. Favorites filter
      await tester.ensureVisible(key('filter-chip-Favorites'));
      await tester.tap(key('filter-chip-Favorites'));
      await tester.pumpAndSettle();
      final favCount = repository.media
          .where((m) => repository.favorites.contains(m.id))
          .length;
      expect(find.byType(MemoryTile), findsNWidgets(favCount));

      // 2. Videos filter
      await tester.ensureVisible(key('filter-chip-Videos'));
      await tester.tap(key('filter-chip-Videos'));
      await tester.pumpAndSettle();
      final videoCount = repository.media
          .where((m) => m.kind == MediaKind.video)
          .length;
      expect(find.byType(MemoryTile), findsNWidgets(videoCount));

      // 3. Photos filter
      await tester.ensureVisible(key('filter-chip-Photos'));
      await tester.tap(key('filter-chip-Photos'));
      await tester.pumpAndSettle();
      // Total photos visible on screen
      expect(find.byType(MemoryTile), findsWidgets);

      // 4. Backed up filter
      await tester.ensureVisible(key('filter-chip-Backed up'));
      await tester.tap(key('filter-chip-Backed up'));
      await tester.pumpAndSettle();
      final syncedCount = repository.media.where((m) => m.isSynced).length;
      expect(find.byType(MemoryTile), findsNWidgets(syncedCount));

      // 5. All resets filter
      await tester.ensureVisible(key('filter-chip-All'));
      await tester.tap(key('filter-chip-All'));
      await tester.pumpAndSettle();
      expect(find.byType(MemoryTile), findsWidgets);
    });

    testWidgets('Search query matches title, filename, and category instantly', (tester) async {
      final repository = await startSearchApp(tester);

      // Search by title/query "lake"
      await tester.tap(key('photo-search'));
      await tester.enterText(key('photo-search'), 'lake');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(key('search-result-summary'), findsOneWidget);
      expect(find.text('1 result'), findsOneWidget);
      expect(key('memory-media-02'), findsOneWidget);

      // Search by category "People"
      await tester.enterText(key('photo-search'), 'People');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final peopleCount = repository.media
          .where((m) => m.category.toLowerCase().contains('people') || m.asset.toLowerCase().contains('people') || m.title.toLowerCase().contains('people'))
          .length;
      expect(find.byType(MemoryTile), findsNWidgets(peopleCount));
    });

    testWidgets('Search query matches date / month name', (tester) async {
      final repository = await startSearchApp(tester);

      // Find an existing media month
      final firstMedia = repository.media.first;
      const monthNames = [
        'jan', 'feb', 'mar', 'apr', 'may', 'jun',
        'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
      ];
      final monthStr = monthNames[firstMedia.takenAt.month - 1];

      await tester.tap(key('photo-search'));
      await tester.enterText(key('photo-search'), monthStr);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(key('search-result-summary'), findsOneWidget);
      expect(find.byType(MemoryTile), findsWidgets);
    });

    testWidgets('Search matches album title and surfaces album media', (tester) async {
      final repository = await startSearchApp(tester);
      expect(repository.albums.isNotEmpty, isTrue);
      final firstAlbum = repository.albums.first;

      await tester.tap(key('photo-search'));
      await tester.enterText(key('photo-search'), firstAlbum.title);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(key('search-result-summary'), findsOneWidget);
      // All items in that album must be visible
      for (final mediaId in firstAlbum.mediaIds) {
        expect(key('memory-$mediaId'), findsOneWidget);
      }
    });

    testWidgets('Empty search shows discovery suggestion chips', (tester) async {
      await startSearchApp(tester);

      // Tap search without entering text
      await tester.tap(key('photo-search'));
      await tester.pumpAndSettle();

      // Quick discovery chips should be visible
      expect(find.text('QUICK DISCOVERY & SUGGESTIONS'), findsOneWidget);
      expect(key('suggestion-favorites'), findsOneWidget);
      expect(key('suggestion-videos'), findsOneWidget);
      expect(key('suggestion-backed-up'), findsOneWidget);
      expect(key('suggestion-on-device'), findsOneWidget);

      // Tap suggestion-favorites
      await tester.tap(key('suggestion-favorites'));
      await tester.pumpAndSettle();

      // Filter is now Favorites
      final favFilter = tester.widget<SpaceFilter>(key('filter-chip-Favorites'));
      expect(favFilter.selected, isTrue);
    });

    testWidgets('Timeline jump sheet allows jumping by year and clearing', (tester) async {
      final repository = await startSearchApp(tester);
      final availableYears = repository.media.map((m) => m.takenAt.year).toSet().toList();
      expect(availableYears.isNotEmpty, isTrue);
      final targetYear = availableYears.first;

      // Open timeline jump sheet
      expect(key('timeline-jump-btn'), findsOneWidget);
      await tester.tap(key('timeline-jump-btn'));
      await tester.pumpAndSettle();

      expect(find.text('Jump in Timeline'), findsOneWidget);
      expect(key('year-jump-$targetYear'), findsOneWidget);

      // Tap year chip
      await tester.tap(key('year-jump-$targetYear'));
      await tester.pumpAndSettle();

      // Active date badge should appear
      expect(key('active-date-badge'), findsOneWidget);
      expect(find.text('Year: $targetYear'), findsOneWidget);
      expect(find.byType(MemoryTile), findsWidgets);

      // Tap clear button on active date badge
      await tester.tap(key('clear-date-filter-btn'));
      await tester.pumpAndSettle();

      expect(key('active-date-badge'), findsNothing);
      expect(find.byType(MemoryTile), findsWidgets);
      expect(key('memory-media-01'), findsOneWidget);
    });

    testWidgets('No match shows friendly empty state with Reset Filters button', (tester) async {
      await startSearchApp(tester);

      // Search for something that does not exist
      await tester.tap(key('photo-search'));
      await tester.enterText(key('photo-search'), 'xyznonexistentquery999');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('A little quiet here'), findsOneWidget);
      expect(key('reset-filters-btn'), findsOneWidget);

      // Tap reset button
      await tester.tap(key('reset-filters-btn'));
      await tester.pumpAndSettle();

      // Search and filters are reset
      expect(find.text('A little quiet here'), findsNothing);
      expect(find.text('Your happy place'), findsOneWidget);
    });
  });
}
