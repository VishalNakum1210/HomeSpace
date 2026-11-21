import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/media_viewer.dart';

void main() {
  testWidgets('MediaViewer displays share button, triggers share, and shows storage details',
      (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = LocalHomeRepository(
      store: MemorySnapshotStore(),
      scenario: DemoScenario.populated,
    );
    await repository.initialize();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      HomeSpaceApp(repository: repository),
    );
    await tester.pumpAndSettle();

    // 1. Open first memory
    await tester.tap(find.byKey(const ValueKey('memory-media-01')));
    await tester.pumpAndSettle();

    expect(find.byType(MediaViewer), findsOneWidget);

    // 2. Share button exists in top app bar
    final shareBtn = find.byKey(const ValueKey('viewer-share'));
    expect(shareBtn, findsOneWidget);

    // 3. Download button still exists in top app bar
    expect(find.byKey(const ValueKey('viewer-download')), findsOneWidget);

    // 4. Tap share button and verify snackbar feedback
    await tester.tap(shareBtn);
    await tester.pumpAndSettle();
    expect(find.textContaining('Sharing'), findsOneWidget);

    // Clear snackbar so it does not obscure bottom bar
    ScaffoldMessenger.of(tester.element(shareBtn)).clearSnackBars();
    await tester.pumpAndSettle();

    // 5. Open photo details via the Info button
    await tester.tap(find.byTooltip('Photo details'));
    await tester.pumpAndSettle();

    // Verify Storage & sync section is present
    expect(find.text('Storage & sync'), findsOneWidget);
    expect(
      find.textContaining('Stored locally on this device')
          .evaluate()
          .isNotEmpty ||
      find.textContaining('Synced to Home Server')
          .evaluate()
          .isNotEmpty,
      isTrue,
    );

    // Close details sheet
    await tester.tap(find.byTooltip('Close photo details'));
    await tester.pumpAndSettle();

    // 6. Test swipe up gesture to open details
    await tester.drag(
      find.byKey(const ValueKey('viewer-pages')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(find.text('Photo details'), findsOneWidget);

    // Close details sheet
    await tester.tap(find.byTooltip('Close photo details'));
    await tester.pumpAndSettle();

    // 7. Test swipe down gesture to close viewer
    await tester.drag(
      find.byKey(const ValueKey('viewer-pages')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MediaViewer), findsNothing);
  });
}
