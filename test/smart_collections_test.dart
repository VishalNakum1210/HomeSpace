import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/smart_collection_page.dart';

Finder key(String value) => find.byKey(ValueKey(value));

Future<LocalHomeRepository> startApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final store = MemorySnapshotStore();
  final repository = LocalHomeRepository(
    store: store,
    initialAppearance: Appearance.light,
  );
  addTearDown(repository.dispose);

  await tester.pumpWidget(HomeSpaceApp(repository: repository));
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

  group('Phase 5: Smart Collections UI Tests', () {
    testWidgets('Collections page renders Smart Folders row (Favorites, Videos, On Device)', (tester) async {
      final repo = await startApp(tester);
      await repo.initialize();

      // Navigate to Collections tab
      await tester.tap(key('tab-collections'));
      await tester.pumpAndSettle();

      expect(key('smart-tile-favorites'), findsOneWidget);
      expect(key('smart-tile-videos'), findsOneWidget);
      expect(key('smart-tile-device'), findsOneWidget);

      expect(find.text('Favorites'), findsWidgets);
      expect(find.text('Videos'), findsWidgets);
      expect(find.text('On Device'), findsWidgets);
    });

    testWidgets('Tapping Favorites tile opens SmartCollectionPage for favorites', (tester) async {
      final repo = await startApp(tester);
      await repo.initialize();

      await repo.setFavorites(['media-01', 'media-02'], true);
      await tester.pumpAndSettle();

      await tester.tap(key('tab-collections'));
      await tester.pumpAndSettle();

      await tester.tap(key('smart-tile-favorites'));
      await tester.pumpAndSettle();

      expect(find.byType(SmartCollectionPage), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Favorites'), findsOneWidget);

      // Verify favorite tiles rendered
      expect(find.byKey(const ValueKey('smart-media-01')), findsOneWidget);
      expect(find.byKey(const ValueKey('smart-media-02')), findsOneWidget);
    });

    testWidgets('Tapping Videos tile opens SmartCollectionPage for videos', (tester) async {
      await startApp(tester);

      await tester.tap(key('tab-collections'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(key('smart-tile-videos'));
      await tester.tap(key('smart-tile-videos'));
      await tester.pumpAndSettle();

      expect(find.byType(SmartCollectionPage), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Videos'), findsOneWidget);
    });

    testWidgets('Tapping On Device tile opens SmartCollectionPage for on-device memories', (tester) async {
      await startApp(tester);

      await tester.tap(key('tab-collections'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(key('smart-tile-device'));
      await tester.tap(key('smart-tile-device'));
      await tester.pumpAndSettle();

      expect(find.byType(SmartCollectionPage), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'On Device'), findsOneWidget);
    });

    testWidgets('SmartCollectionPage selection mode allows toggling favorite and bulk add to album', (tester) async {
      final repo = await startApp(tester);
      await repo.initialize();

      await repo.setFavorites(['media-01'], true);
      await tester.pumpAndSettle();

      await tester.tap(key('tab-collections'));
      await tester.pumpAndSettle();

      await tester.tap(key('smart-tile-favorites'));
      await tester.pumpAndSettle();

      // Long press on a memory tile to trigger selection mode
      await tester.longPress(find.byKey(const ValueKey('smart-media-01')));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Unfavorite'), findsOneWidget);
      expect(find.text('Add to album'), findsOneWidget);

      // Tap Unfavorite
      await tester.tap(find.text('Unfavorite'));
      await tester.pumpAndSettle();

      expect(repo.favorites.contains('media-01'), isFalse);
    });
  });
}
