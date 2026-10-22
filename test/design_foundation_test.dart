import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/design/space_navigation.dart';
import 'package:homespace/design/space_theme.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/data/seed_library.dart';
import 'package:homespace/domain/models.dart';

Future<void> startApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = LocalHomeRepository(
    store: MemorySnapshotStore(),
    initialAppearance: Appearance.light,
  );
  addTearDown(repository.dispose);
  await tester.pumpWidget(HomeSpaceApp(repository: repository));
  await tester.pumpAndSettle();
}

Future<void> openTab(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey('tab-$name')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf'));
    await font.load();
  });

  test('Bundled preview media and local font are available offline', () {
    for (final photo in seedLibrary(DateTime.now()).media) {
      expect(File(photo.asset).lengthSync(), greaterThan(20000));
    }
    expect(
      File('assets/fonts/Nunito-Variable.ttf').lengthSync(),
      greaterThan(200000),
    );
    expect(File('assets/fonts/OFL.txt').existsSync(), isTrue);
  });

  testWidgets('Icon-only navigation keeps a blue circle on every active tab', (
    tester,
  ) async {
    await startApp(tester);
    final navigation = find.byType(SpaceNavigation);
    expect(tester.getSize(navigation), const Size(216, 64));
    expect(
      find.descendant(of: navigation, matching: find.byType(Text)),
      findsNothing,
    );
    Color? blue;
    double previousX = -1;
    for (final page in SpacePage.values) {
      await openTab(tester, page.name);
      final circle = find.byKey(const ValueKey('active-tab-circle'));
      final decoration =
          tester.widget<DecoratedBox>(circle).decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(tester.getSize(circle), const Size.square(48));
      blue ??= decoration.color;
      expect(decoration.color, blue);
      expect(tester.getCenter(circle).dx, greaterThan(previousX));
      previousX = tester.getCenter(circle).dx;
      expect(SpaceStyle.of(tester.element(navigation)).accent, page.color);
      final semantics = tester.getSemantics(
        find.byKey(ValueKey('tab-${page.name}')),
      );
      expect(semantics.label, page.label);
      expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Appearance choice carries across pages and follows system brightness',
    (tester) async {
      await startApp(tester);
      await openTab(tester, 'profile');
      await tester.tap(find.byKey(const ValueKey('appearance-setting')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(SpaceNavigation))).brightness,
        Brightness.dark,
      );
      await openTab(tester, 'collections');
      expect(
        Theme.of(tester.element(find.byType(SpaceNavigation))).brightness,
        Brightness.dark,
      );
      await openTab(tester, 'profile');
      await tester.tap(find.byKey(const ValueKey('appearance-setting')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('theme-system')));
      await tester.pumpAndSettle();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(SpaceNavigation))).brightness,
        Brightness.light,
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(SpaceNavigation))).brightness,
        Brightness.dark,
      );
    },
  );

  testWidgets('Photos retain scroll position and search across tab changes', (
    tester,
  ) async {
    await startApp(tester, size: const Size(390, 700));
    final photos = find.byKey(const PageStorageKey('photos-scroll'));
    await tester.drag(photos, const Offset(0, -220));
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(of: photos, matching: find.byType(Scrollable))
        .first;
    final offset = tester.state<ScrollableState>(scroll).position.pixels;
    expect(offset, greaterThan(0));
    await openTab(tester, 'collections');
    await openTab(tester, 'photos');
    expect(tester.state<ScrollableState>(scroll).position.pixels, offset);
    await tester.drag(photos, const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('photo-search')),
      'not-a-memory',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('A little quiet here'), findsOneWidget);
    await openTab(tester, 'profile');
    await openTab(tester, 'photos');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('photo-search')))
          .controller!
          .text,
      'not-a-memory',
    );
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets(
    'Collection filters and album preview have consistent sample content',
    (tester) async {
      await startApp(tester);
      await openTab(tester, 'collections');
      expect(find.text('4 albums'), findsOneWidget);
      await tester.tap(find.text('Shared').first);
      await tester.pumpAndSettle();
      expect(find.text('2 albums'), findsOneWidget);
      expect(find.text('By the water'), findsNothing);
      await tester.tap(find.text('Family weekends'));
      await tester.pumpAndSettle();
      expect(find.text('SHARED ALBUM'), findsOneWidget);
      expect(find.text('A space for 3 family members'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mine'));
      await tester.pumpAndSettle();
      expect(find.text('By the water'), findsOneWidget);
      expect(find.text('Family weekends'), findsNothing);
    },
  );

  testWidgets('Android Back returns to Photos from a primary tab', (
    tester,
  ) async {
    await startApp(tester);
    await openTab(tester, 'collections');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester.widget<SpaceNavigation>(find.byType(SpaceNavigation)).selected,
      SpacePage.photos,
    );
  });

  testWidgets(
    'Narrow screens, landscape, and double-size text avoid overflow',
    (tester) async {
      await startApp(tester, size: const Size(320, 700));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final size in [const Size(320, 700), const Size(740, 360)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        for (final page in SpacePage.values) {
          await openTab(tester, page.name);
          expect(
            tester.takeException(),
            isNull,
            reason: '${page.label} at $size',
          );
        }
      }
    },
  );

  testWidgets(
    'Navigation and controls have accessible labels and Android touch targets',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await startApp(tester);
        for (final page in SpacePage.values) {
          await openTab(tester, page.name);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets('Reduced motion removes navigation travel', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await startApp(tester);
    await openTab(tester, 'collections');
    final positioned = tester.widget<AnimatedPositioned>(
      find.descendant(
        of: find.byType(SpaceNavigation),
        matching: find.byType(AnimatedPositioned),
      ),
    );
    expect(positioned.duration, Duration.zero);
    expect(tester.takeException(), isNull);
  });
}
