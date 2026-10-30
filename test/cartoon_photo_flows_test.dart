import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/media_viewer.dart';
import 'package:homespace/design/space_navigation.dart';
import 'package:homespace/design/space_theme.dart';

const frame = ValueKey('photo-flow-frame');
Finder key(String value) => find.byKey(ValueKey(value));

Future<LocalHomeRepository> start(WidgetTester tester) async {
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
    RepaintBoundary(
      key: frame,
      child: HomeSpaceApp(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
  if (const bool.fromEnvironment('HOMESPACE_CAPTURE')) {
    final context = tester.element(find.text('Your happy place'));
    await tester.runAsync(() async {
      for (final asset
          in Directory('assets/illustrations/vector')
              .listSync()
              .whereType<File>()
              .where((asset) => asset.path.endsWith('.svg'))) {
        final loader = SvgAssetLoader(asset.path.replaceAll('\\', '/'));
        await svg.cache.putIfAbsent(
          loader.cacheKey(context),
          () => loader.loadBytes(context),
        );
      }
      for (final media in repository.media) {
        await precacheImage(AssetImage(media.asset), context);
      }
    });
    await tester.pumpAndSettle();
  }
  return repository;
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('HOMESPACE_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(frame),
  );
  void repaint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  repaint(boundary);
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('output/previews/cartoon-phase-2-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'Search retains its input while becoming compact and Back exits it',
    (tester) async {
      final repository = await start(tester);
      await tester.tap(key('photo-search'));
      await tester.pumpAndSettle();
      await tester.enterText(key('photo-search'), 'lake');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Your happy place'), findsNothing);
      expect(key('search-result-summary'), findsOneWidget);
      expect(find.text('1 result'), findsOneWidget);
      expect(find.byTooltip('Close search'), findsOneWidget);
      expect(key('memory-media-02'), findsOneWidget);
      await capture(tester, 'search-light');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Your happy place'), findsOneWidget);
      expect(
        tester.widget<TextField>(key('photo-search')).controller!.text,
        isEmpty,
      );
      expect(repository.media.length, 12);
    },
  );

  testWidgets(
    'Back from another tab preserves photo search until Photos handles Back',
    (tester) async {
      final repository = await start(tester);
      final saved = (repository.store as MemorySnapshotStore).contents;
      for (final tab in ['collections', 'profile']) {
        await tester.tap(key('photo-search'));
        await tester.enterText(key('photo-search'), 'lake');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        tester
            .widget<SpaceNavigation>(
              find.byType(SpaceNavigation, skipOffstage: false),
            )
            .onSelected(SpacePage.values.byName(tab));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(key('search-result-summary'), findsOneWidget);
        expect(
          tester.widget<TextField>(key('photo-search')).controller!.text,
          'lake',
        );
        expect(key('memory-media-02'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(key('photo-search')).controller!.text,
          isEmpty,
        );
        expect(find.text('Your happy place'), findsOneWidget);
      }
      expect((repository.store as MemorySnapshotStore).contents, saved);
    },
  );

  testWidgets(
    'Back from another tab preserves photo selection until Photos handles Back',
    (tester) async {
      final repository = await start(tester);
      final saved = (repository.store as MemorySnapshotStore).contents;
      for (final tab in ['collections', 'profile']) {
        await tester.longPress(key('memory-media-01'));
        await tester.pumpAndSettle();
        await tester.tap(key('memory-media-02'));
        await tester.pumpAndSettle();
        tester
            .widget<SpaceNavigation>(
              find.byType(SpaceNavigation, skipOffstage: false),
            )
            .onSelected(SpacePage.values.byName(tab));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('2 selected'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('2 selected'), findsNothing);
        expect(find.text('Your happy place'), findsOneWidget);
      }
      expect((repository.store as MemorySnapshotStore).contents, saved);
    },
  );

  testWidgets(
    'Selection actions stay clear of the dock and Clear selection is transient',
    (tester) async {
      final repository = await start(tester);
      await tester.longPress(key('memory-media-01'));
      await tester.pumpAndSettle();
      await tester.tap(key('memory-media-02'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byType(SpaceNavigation), findsNothing);
      final screenBottom = tester.view.physicalSize.height;
      expect(tester.getRect(key('bulk-trash')).bottom, lessThan(screenBottom));
      expect(
        tester.getRect(key('clear-photo-selection')).bottom,
        lessThanOrEqualTo(screenBottom),
      );
      await capture(tester, 'selection-light');
      tester.view.physicalSize = const Size(320, 700);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(key('clear-photo-selection'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsNothing);
      expect(repository.trash, isEmpty);
      expect(repository.media.length, 12);
    },
  );

  testWidgets(
    'Photo details follow appearance and expose actual sample metadata',
    (tester) async {
      final repository = await start(tester);
      for (final appearance in [Appearance.light, Appearance.dark]) {
        await repository.setAppearance(appearance);
        await tester.pumpAndSettle();
        await tester.tap(key('memory-media-01'));
        await tester.pumpAndSettle();
        if (appearance == Appearance.light) await capture(tester, 'viewer');
        await tester.tap(find.byTooltip('Photo details'));
        await tester.pumpAndSettle();
        expect(find.text('Photo details'), findsOneWidget);
        expect(find.text('photo_01.jpg'), findsOneWidget);
        expect(find.text('Added by'), findsOneWidget);
        expect(find.text('Maya'), findsWidgets);
        expect(
          Theme.of(tester.element(find.text('Photo details'))).brightness,
          appearance == Appearance.light ? Brightness.light : Brightness.dark,
        );
        await capture(tester, 'details-${appearance.name}');
        await tester.tap(find.byTooltip('Close photo details'));
        await tester.pumpAndSettle();
        expect(find.byType(MediaViewer), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'Hidden viewer controls give the canvas its full height and can be restored',
    (tester) async {
      await start(tester);
      await tester.tap(key('memory-media-01'));
      await tester.pumpAndSettle();
      final initial = tester.getSize(key('viewer-pages')).height;
      expect(initial, greaterThan(600));
      await tester.tap(key('viewer-pages'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(tester.getSize(key('viewer-pages')).height, greaterThan(initial));
      await tester.tap(find.byTooltip('Show controls'));
      await tester.pumpAndSettle();
      expect(tester.getSize(key('viewer-pages')).height, initial);
      expect(tester.takeException(), isNull);
    },
  );
}
