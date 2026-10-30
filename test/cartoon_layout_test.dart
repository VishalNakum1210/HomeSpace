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

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('Main pages preserve usable actions above the floating dock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = LocalHomeRepository(
      store: MemorySnapshotStore(),
      initialAppearance: Appearance.light,
    );
    addTearDown(repository.dispose);
    const captureKey = ValueKey('cartoon-capture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: HomeSpaceApp(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    if (const bool.fromEnvironment('HOMESPACE_CAPTURE')) {
      await tester.runAsync(() async {
        final context = tester.element(find.text('Your happy place'));
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

    Future<void> capture(String name) async {
      if (!const bool.fromEnvironment('HOMESPACE_CAPTURE')) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      // Repaint retained IndexedStack layers before exporting the active tab.
      void repaint(RenderObject object) {
        object.markNeedsPaint();
        object.visitChildren(repaint);
      }

      repaint(boundary);
      await tester.pump();
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('output/previews/cartoon-phase-1-$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final appearance in [Appearance.light, Appearance.dark]) {
      await repository.setAppearance(appearance);
      await tester.pumpAndSettle();
      for (final page in ['photos', 'collections', 'profile']) {
        await tester.tap(find.byKey(ValueKey('tab-$page')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (page == 'collections' || page == 'profile') {
          final action = find.byKey(
            ValueKey(page == 'collections' ? 'new-album' : 'edit-profile'),
          );
          final dock = tester.getRect(
            find.byKey(const ValueKey('space-navigation')),
          );
          final rect = tester.getRect(action);
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(
            rect.bottom,
            lessThanOrEqualTo(dock.top),
            reason: '$page action must stay above the dock at default size',
          );
        }
        await capture('$page-${appearance.name}');
      }
    }
    await tester.tap(find.byKey(const ValueKey('tab-photos')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    expect(find.text('A little quiet here'), findsOneWidget);
    expect(repository.media.length, 12);
    await tester.tap(find.text('All').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('memory-media-01')), findsOneWidget);
  });
}
