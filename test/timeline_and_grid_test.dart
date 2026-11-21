import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/application/frontend_session.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/pages/library_widgets.dart';

void main() {
  testWidgets('PhotosPage renders grid density toggle, sync badges, and bulk-share in selection mode',
      (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = LocalHomeRepository(
      store: MemorySnapshotStore(),
      scenario: DemoScenario.populated,
    );
    final session = FrontendSession();
    await session.setAuthenticated(
      serverUri: Uri.parse('https://example.com'),
      token: 'valid_token',
      userId: 'user_1',
      email: 'user@example.com',
      name: 'Vishal',
    );
    addTearDown(repository.dispose);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      HomeSpaceApp(
        repository: repository,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    // 1. Grid density toggle button is rendered
    expect(find.byKey(const ValueKey('grid-density-toggle')), findsOneWidget);

    // 2. Sync status badges are rendered on memory tiles
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.icon == Icons.cloud_queue_rounded ||
                w.icon == Icons.cloud_done_rounded),
      ),
      findsWidgets,
    );

    // 3. Cycle grid density by tapping toggle
    await tester.tap(find.byKey(const ValueKey('grid-density-toggle')));
    await tester.pumpAndSettle();

    // 4. Test multi-select mode
    final firstMemory = find.byType(MemoryTile).first;
    await tester.ensureVisible(firstMemory);
    await tester.longPress(firstMemory);
    await tester.pumpAndSettle();

    // Verify all 4 actions are available in the floating action bar
    expect(find.byKey(const ValueKey('bulk-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-favorite')), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-album')), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-trash')), findsOneWidget);

    // Tap share button
    await tester.tap(find.byKey(const ValueKey('bulk-share')));
    await tester.pumpAndSettle();

    // Verify snackbar feedback
    expect(find.textContaining('Sharing 1 memory…'), findsOneWidget);
  });

  testWidgets('Repository clearUserData clears media and resetToDemo restores them',
      (tester) async {
    final repository = LocalHomeRepository(
      store: MemorySnapshotStore(),
      scenario: DemoScenario.populated,
    );
    await repository.initialize();
    addTearDown(repository.dispose);

    expect(repository.media.isNotEmpty, isTrue);
    expect(repository.albums.isNotEmpty, isTrue);

    // Clear user data
    await repository.clearUserData();
    expect(repository.media.isEmpty, isTrue);
    expect(repository.albums.isEmpty, isTrue);
    expect(repository.trash.isEmpty, isTrue);

    // Restore demo
    await repository.resetToDemo();
    expect(repository.media.isNotEmpty, isTrue);
    expect(repository.albums.isNotEmpty, isTrue);
  });
}
