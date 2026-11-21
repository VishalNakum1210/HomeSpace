import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/application/frontend_session.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/pages/splash_page.dart';

void main() {
  testWidgets('SplashPage renders logo, title, and tagline, then initializes',
      (tester) async {
    bool initialized = false;
    final repository = LocalHomeRepository(store: MemorySnapshotStore());
    final session = FrontendSession();
    addTearDown(repository.dispose);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SplashPage(
          session: session,
          repository: repository,
          onInitialized: () {
            initialized = true;
          },
        ),
      ),
    );

    expect(find.text('HomeSpace'), findsOneWidget);
    expect(find.text("Your family's private memory cloud"), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
    expect(find.text('© 2026 Vishal Nakum'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(initialized, isFalse);

    await tester.pump(const Duration(milliseconds: 750));
    expect(initialized, isTrue);
  });

  testWidgets('HomeSpaceApp auto-routes to photos feed when session is already authenticated',
      (tester) async {
    final repository = LocalHomeRepository(store: MemorySnapshotStore());
    final session = FrontendSession();
    await session.setAuthenticated(
      serverUri: Uri.parse('https://example.com'),
      token: 'valid_token',
      userId: 'user_1',
      email: 'user@example.com',
      name: 'Test User',
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

    // Verify user is directly in the Photos page without ever seeing AuthPage
    expect(find.text('Log in'), findsNothing);
    expect(find.text('Create account'), findsNothing);
    expect(find.byKey(const ValueKey('space-navigation')), findsOneWidget);
  });
}
