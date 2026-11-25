import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/app.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/domain/pin_security.dart';
import 'package:homespace/pages/admin_users_page.dart';
import 'package:homespace/pages/app_lock_page.dart';
import 'package:homespace/services/cache_service.dart';
import 'package:homespace/widgets/storage_meter_card.dart';

Finder key(String value) => find.byKey(ValueKey(value));

Future<LocalHomeRepository> startProfileApp(WidgetTester tester) async {
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
  late Directory isolatedTestCacheDir;

  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    isolatedTestCacheDir = Directory(
      '${Directory.systemTemp.path}/hs_test_cache_${DateTime.now().millisecondsSinceEpoch}',
    )..createSync(recursive: true);
    CacheService.customCacheDir = isolatedTestCacheDir;

    await (FontLoader('Nunito')
          ..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  tearDownAll(() {
    CacheService.customCacheDir = null;
    try {
      if (isolatedTestCacheDir.existsSync()) {
        isolatedTestCacheDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Phase 9: Profile, Settings, Admin Family Management & App Lock', () {
    testWidgets('StorageMeterCard renders Google Photos style multi-segment meter and clears cache', (tester) async {
      await startProfileApp(tester);

      // Navigate to Profile tab
      await tester.tap(find.byKey(const ValueKey('tab-profile')));
      await tester.pumpAndSettle();

      // Open Storage & Space directly from Profile page
      expect(key('storage-setting'), findsOneWidget);
      await tester.tap(key('storage-setting'));
      await tester.pumpAndSettle();

      expect(find.byType(StorageMeterCard), findsOneWidget);
      expect(find.text('Storage & Space'), findsWidgets);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(key('clear-cache-btn'), findsOneWidget);

      // Tap clear cache button
      await tester.tap(key('clear-cache-btn'));
      await tester.pumpAndSettle();

      expect(find.text('Cache is clean (0 B)'), findsOneWidget);
    });

    testWidgets('Admin family management lists, adds, and removes family members', (tester) async {
      await startProfileApp(tester);

      // Navigate to Profile tab
      await tester.tap(find.byKey(const ValueKey('tab-profile')));
      await tester.pumpAndSettle();

      // Open Family Management directly from Profile page
      expect(key('family-admin-setting'), findsOneWidget);
      await tester.ensureVisible(key('family-admin-setting'));
      await tester.pumpAndSettle();
      await tester.tap(key('family-admin-setting'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminUsersPage), findsOneWidget);
      expect(find.text('Maya'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);

      // Tap Add Member button
      expect(key('add-family-member-btn'), findsOneWidget);
      await tester.tap(key('add-family-member-btn'));
      await tester.pumpAndSettle();

      expect(find.text('Add Family Member'), findsOneWidget);
      await tester.enterText(key('add-member-name'), 'Papa');
      await tester.enterText(key('add-member-email'), 'papa@homespace.local');
      await tester.enterText(key('add-member-password'), 'password123');
      await tester.tap(key('add-member-admin-switch'));
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(key('submit-add-member-btn'));
      await tester.pumpAndSettle();

      expect(find.text('Papa'), findsOneWidget);

      // Remove a member (Alex)
      expect(key('delete-member-member-alex'), findsOneWidget);
      await tester.tap(key('delete-member-member-alex'));
      await tester.pumpAndSettle();

      expect(find.text('Remove Alex?'), findsOneWidget);
      await tester.tap(find.text('Remove User'));
      await tester.pumpAndSettle();

      expect(find.text('Alex'), findsNothing);
    });

    testWidgets('App Lock settings toggles PIN protection and enforces PIN on open', (tester) async {
      final repository = await startProfileApp(tester);

      // Navigate to Profile tab
      await tester.tap(find.byKey(const ValueKey('tab-profile')));
      await tester.pumpAndSettle();

      // Open App Lock & Privacy directly from Profile page
      expect(key('app-lock-setting'), findsOneWidget);
      await tester.ensureVisible(key('app-lock-setting'));
      await tester.pumpAndSettle();
      await tester.tap(key('app-lock-setting'));
      await tester.pumpAndSettle();

      expect(find.byType(AppLockPage), findsOneWidget);
      expect(key('app-lock-switch'), findsOneWidget);

      // Toggle switch to enable
      await tester.tap(key('app-lock-switch'));
      await tester.pumpAndSettle();

      // Modal dialog asks for 4-digit PIN
      expect(find.text('Set 4-Digit PIN'), findsOneWidget);
      await tester.enterText(key('pin-input-field'), '2580');
      await tester.enterText(key('pin-confirm-input-field'), '2580');
      await tester.tap(key('save-pin-btn'));
      await tester.pumpAndSettle();

      expect(repository.profile.appLockEnabled, isTrue);
      expect(repository.profile.appLockPin, isNot('2580'));
      expect(PinSecurity.verifyPin('2580', repository.profile.appLockPin), isTrue);

      // Pop back to main app
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Simulate app backgrounded and resumed
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // App lock screen is displayed
      expect(key('app-lock-screen'), findsOneWidget);
      expect(find.text('HomeSpace is Locked'), findsOneWidget);

      // Enter incorrect PIN: 1, 1, 1, 1
      await tester.tap(key('pin-key-1'));
      await tester.pump();
      await tester.tap(key('pin-key-1'));
      await tester.pump();
      await tester.tap(key('pin-key-1'));
      await tester.pump();
      await tester.tap(key('pin-key-1'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);
      expect(key('app-lock-screen'), findsOneWidget);

      // Enter correct PIN: 2, 5, 8, 0
      await tester.tap(key('pin-key-2'));
      await tester.pump();
      await tester.tap(key('pin-key-5'));
      await tester.pump();
      await tester.tap(key('pin-key-8'));
      await tester.pump();
      await tester.tap(key('pin-key-0'));
      await tester.pumpAndSettle();

      // App is unlocked
      expect(key('app-lock-screen'), findsNothing);
      expect(find.text('Hi, Maya!'), findsOneWidget);
    });

    testWidgets('Edit profile allows updating name and avatar tone', (tester) async {
      final repository = await startProfileApp(tester);

      // Navigate to Profile tab
      await tester.tap(find.byKey(const ValueKey('tab-profile')));
      await tester.pumpAndSettle();

      // Tap Edit Profile
      expect(key('edit-profile'), findsOneWidget);
      await tester.tap(key('edit-profile'));
      await tester.pumpAndSettle();

      // Edit name to "Super Maya"
      await tester.enterText(key('profile-name'), 'Super Maya');
      await tester.tap(key('save-profile'));
      await tester.pumpAndSettle();

      // Returned to Profile page with new name
      expect(find.text('Hi, Super Maya!'), findsOneWidget);
      expect(repository.profile.name, 'Super Maya');
    });
  });
}
