import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';

Future<void> openPhoto(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
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
  await tester.tap(find.byKey(const ValueKey('memory-media-01')));
  await tester.pumpAndSettle();
}

Finder get photoSurface => find.ancestor(
  of: find
      .byWidgetPredicate(
        (widget) => widget is Image && widget.semanticLabel != null,
      )
      .first,
  matching: find.byType(InteractiveViewer),
);

Matrix4 photoTransform(WidgetTester tester) => tester
    .widget<InteractiveViewer>(photoSurface)
    .transformationController!
    .value
    .clone();

Future<(TestGesture, TestGesture)> pinchOut(WidgetTester tester) async {
  final center = tester.getCenter(photoSurface);
  final first = await tester.startGesture(
    center + const Offset(-45, 0),
    pointer: 1,
  );
  final second = await tester.startGesture(
    center + const Offset(45, 0),
    pointer: 2,
  );
  for (var step = 1; step <= 5; step++) {
    await first.moveTo(center + Offset(-45 - step * 13, 0));
    await second.moveTo(center + Offset(45 + step * 13, 0));
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(photoTransform(tester).getMaxScaleOnAxis(), greaterThan(1.6));
  return (first, second);
}

void main() {
  testWidgets(
    'Adding a second finger during a long swipe zooms the original photo',
    (tester) async {
      await openPhoto(tester);
      final bounds = tester.getRect(photoSurface);
      final first = await tester.startGesture(
        Offset(bounds.right - 30, bounds.center.dy),
        pointer: 1,
      );
      for (var step = 0; step < 12; step++) {
        await first.moveBy(const Offset(-22, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final second = await tester.startGesture(
        bounds.center + const Offset(30, 0),
        pointer: 2,
      );
      for (var step = 1; step <= 5; step++) {
        await first.moveBy(const Offset(-12, 0));
        await second.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(photoTransform(tester).getMaxScaleOnAxis(), greaterThan(1.5));
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('viewer-position')))
            .label,
        contains('1 of 12 memories'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A cancelled swipe leaves the next pinch responsive', (
    tester,
  ) async {
    await openPhoto(tester);
    final first = await tester.startGesture(
      tester.getCenter(photoSurface),
      pointer: 5,
    );
    await first.moveBy(const Offset(-80, 0));
    await tester.pump(const Duration(milliseconds: 30));
    await first.cancel();
    await tester.pumpAndSettle();
    final (left, right) = await pinchOut(tester);
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('viewer-position'))).label,
      contains('1 of 12 memories'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A small first-finger drag can become a pinch without another tap',
    (tester) async {
      await openPhoto(tester);
      final center = tester.getCenter(photoSurface);
      final first = await tester.startGesture(
        center + const Offset(-45, 0),
        pointer: 1,
      );
      await first.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 40));
      final second = await tester.startGesture(
        center + const Offset(45, 0),
        pointer: 2,
      );
      for (var step = 1; step <= 5; step++) {
        await first.moveTo(center + Offset(-75 - step * 15, 0));
        await second.moveTo(center + Offset(45 + step * 15, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(photoTransform(tester).getMaxScaleOnAxis(), greaterThan(1.5));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('viewer-position')))
            .label,
        contains('1 of 12 memories'),
      );
    },
  );

  testWidgets(
    'Lifting one pinch finger immediately permits one-finger panning',
    (tester) async {
      await openPhoto(tester);
      final (first, second) = await pinchOut(tester);
      final before = photoTransform(tester);
      await first.up();
      await tester.pump();
      await second.moveBy(const Offset(-40, 24));
      await tester.pump(const Duration(milliseconds: 40));
      await second.moveBy(const Offset(-30, 12));
      await tester.pump(const Duration(milliseconds: 40));
      final after = photoTransform(tester);
      expect(
        after.getMaxScaleOnAxis(),
        closeTo(before.getMaxScaleOnAxis(), .01),
      );
      expect(
        after.getTranslation().x,
        lessThan(before.getTranslation().x - 20),
      );
      await second.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('viewer-position')))
            .label,
        contains('1 of 12 memories'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'After pinch release the next drag and pinch need no unlocking tap',
    (tester) async {
      await openPhoto(tester);
      final (first, second) = await pinchOut(tester);
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final before = photoTransform(tester);
      await tester.drag(photoSurface, const Offset(-55, 20));
      await tester.pumpAndSettle();
      expect(
        photoTransform(tester).getTranslation().x,
        lessThan(before.getTranslation().x - 20),
      );
      final center = tester.getCenter(photoSurface);
      final left = await tester.startGesture(
        center + const Offset(-90, 0),
        pointer: 3,
      );
      final right = await tester.startGesture(
        center + const Offset(90, 0),
        pointer: 4,
      );
      for (var step = 1; step <= 6; step++) {
        await left.moveTo(center + Offset(-90 + step * 12, 0));
        await right.moveTo(center + Offset(90 - step * 12, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await left.up();
      await right.up();
      await tester.pumpAndSettle();
      expect(photoTransform(tester).getMaxScaleOnAxis(), closeTo(1, .02));
      await tester.drag(
        find.byKey(const ValueKey('viewer-pages')),
        const Offset(-320, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('viewer-position')))
            .label,
        contains('2 of 12 memories'),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
