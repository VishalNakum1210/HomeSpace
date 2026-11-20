import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/application/frontend_session.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';

Finder key(String value) => find.byKey(ValueKey(value));

void main() {
  setUpAll(() async {
    await (FontLoader('Nunito')
          ..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  testWidgets(
    'Registration allows avatar tone selection and local account creation on SSL/TLS failure',
    (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = LocalHomeRepository(store: MemorySnapshotStore());
      final session = FrontendSession(
        serverUri: Uri.parse('https://invalid-nonexistent-server-for-test.ts.net:8443'),
      );
      addTearDown(repository.dispose);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        HomeSpaceApp(repository: repository, session: session),
      );
      await tester.pumpAndSettle();

      // Switch to Registration
      await tester.ensureVisible(key('auth-switch'));
      await tester.tap(key('auth-switch'));
      await tester.pumpAndSettle();

      expect(find.text('Join your HomeSpace'), findsOneWidget);
      expect(find.text('Avatar color'), findsOneWidget);

      // Select green avatar tone
      await tester.ensureVisible(key('auth-avatar-green'));
      await tester.tap(key('auth-avatar-green'));
      await tester.pumpAndSettle();

      // Fill in details
      await tester.ensureVisible(key('auth-Full name'));
      await tester.enterText(key('auth-Full name'), 'Alex Green');
      await tester.enterText(key('auth-Email'), 'alex@example.com');
      await tester.enterText(key('auth-Password'), 'supersecret123');
      await tester.enterText(key('auth-Confirm password'), 'supersecret123');
      await tester.pumpAndSettle();

      // Submit registration
      await tester.ensureVisible(key('auth-submit'));
      await tester.tap(key('auth-submit'));
      await tester.pumpAndSettle();

      // Verify the user is authenticated directly and enters the app
      expect(session.isAuthenticated, isTrue);
      expect(session.userName, 'Alex Green');
      expect(session.userEmail, 'alex@example.com');
      expect(session.avatarTone, AvatarTone.green);
      expect(session.isOpen, isTrue);

      // Verify navigation is displayed
      expect(key('space-navigation'), findsOneWidget);
    },
  );

  testWidgets(
    'Registration without configured server creates local account directly upon confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = LocalHomeRepository(store: MemorySnapshotStore());
      final session = FrontendSession(serverUri: null);
      addTearDown(repository.dispose);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        HomeSpaceApp(repository: repository, session: session),
      );
      await tester.pumpAndSettle();

      // Switch to Registration
      await tester.ensureVisible(key('auth-switch'));
      await tester.tap(key('auth-switch'));
      await tester.pumpAndSettle();

      // Select blue avatar
      await tester.ensureVisible(key('auth-avatar-blue'));
      await tester.tap(key('auth-avatar-blue'));
      await tester.pumpAndSettle();

      // Fill details
      await tester.ensureVisible(key('auth-Full name'));
      await tester.enterText(key('auth-Full name'), 'Sam Blue');
      await tester.enterText(key('auth-Email'), 'sam@example.com');
      await tester.enterText(key('auth-Password'), 'pass123456');
      await tester.enterText(key('auth-Confirm password'), 'pass123456');
      await tester.pumpAndSettle();

      // Submit
      await tester.ensureVisible(key('auth-submit'));
      await tester.tap(key('auth-submit'));
      await tester.pumpAndSettle();

      // Verify session and entry directly without dialogs
      expect(session.isAuthenticated, isTrue);
      expect(session.userName, 'Sam Blue');
      expect(session.avatarTone, AvatarTone.blue);
      expect(session.isOpen, isTrue);
    },
  );

  testWidgets(
    'Login enters Local Mode seamlessly on SSL/TLS failure without blocking error',
    (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = LocalHomeRepository(store: MemorySnapshotStore());
      final session = FrontendSession(
        serverUri: Uri.parse('https://invalid-nonexistent-server-for-test.ts.net:8443'),
      );
      addTearDown(repository.dispose);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        HomeSpaceApp(repository: repository, session: session),
      );
      await tester.pumpAndSettle();

      // On Login page: "Welcome home"
      expect(find.text('Welcome home'), findsOneWidget);

      // Enter login credentials
      await tester.enterText(key('auth-Email'), 'vishal@example.com');
      await tester.enterText(key('auth-Password'), 'secret1234');
      await tester.pumpAndSettle();

      // Tap Log in
      await tester.ensureVisible(key('auth-submit'));
      await tester.tap(key('auth-submit'));
      await tester.pumpAndSettle();

      // Should seamlessly authenticate and enter app without SSL/TLS error alert
      expect(session.isAuthenticated, isTrue);
      expect(session.userEmail, 'vishal@example.com');
      expect(session.userName, 'Vishal');
      expect(session.isOpen, isTrue);
      expect(key('space-navigation'), findsOneWidget);
    },
  );

  testWidgets(
    'Forgot password dialog offers direct sign in in Local Mode',
    (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = LocalHomeRepository(store: MemorySnapshotStore());
      final session = FrontendSession(
        serverUri: Uri.parse('https://invalid-nonexistent-server-for-test.ts.net:8443'),
      );
      addTearDown(repository.dispose);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        HomeSpaceApp(repository: repository, session: session),
      );
      await tester.pumpAndSettle();

      // Tap Forgot password?
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in in Local Mode'), findsOneWidget);
      await tester.tap(find.text('Sign in in Local Mode'));
      await tester.pumpAndSettle();

      expect(session.isAuthenticated, isTrue);
      expect(session.isOpen, isTrue);
      expect(key('space-navigation'), findsOneWidget);
    },
  );
}
