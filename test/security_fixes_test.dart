import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homespace/application/frontend_session.dart';
import 'package:homespace/application/home_scope.dart';
import 'package:homespace/data/homespace_api_client.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_codec.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/data/tls_trust.dart';
import 'package:homespace/design/space_theme.dart';
import 'package:homespace/domain/models.dart';
import 'package:homespace/domain/pin_security.dart';
import 'package:homespace/pages/app_lock_page.dart';
import 'package:homespace/pages/auth_page.dart';
import 'package:homespace/pages/trash_page.dart';
import 'package:homespace/services/cache_service.dart';

class _OrphanTrashRepository extends LocalHomeRepository {
  _OrphanTrashRepository({required super.store});

  @override
  List<TrashEntry> get trash => [
    TrashEntry('orphaned-missing-id', DateTime.utc(2026, 1, 1)),
    ...super.trash,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Security & Reliability Regressions', () {
    test('PinSecurity hashes with unique salts and verifies accurately', () {
      final hashA = PinSecurity.hashPin('4242');
      final hashB = PinSecurity.hashPin('4242');

      expect(PinSecurity.isHashed(hashA), isTrue);
      expect(PinSecurity.isHashed('4242'), isFalse);
      expect(hashA, isNot(equals(hashB)));
      expect(PinSecurity.verifyPin('4242', hashA), isTrue);
      expect(PinSecurity.verifyPin('4242', hashB), isTrue);
      expect(PinSecurity.verifyPin('0000', hashA), isFalse);
      expect(PinSecurity.verifyPin('', hashA), isFalse);

      // Legacy plaintext migration support
      expect(PinSecurity.verifyPin('1357', '1357'), isTrue);
      expect(PinSecurity.verifyPin('9999', '1357'), isFalse);
    });

    test('HomeSpaceTlsTrust persists SHA-256 leaf pins and classifies local hosts', () async {
      final tempDir = Directory.systemTemp.createTempSync('homespace_tls_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      expect(HomeSpaceTlsTrust.isPrivateOrLocalHost('100.64.1.2'), isTrue);
      expect(HomeSpaceTlsTrust.isPrivateOrLocalHost('192.168.1.50'), isTrue);
      expect(HomeSpaceTlsTrust.isPrivateOrLocalHost('homespace.local'), isTrue);
      expect(HomeSpaceTlsTrust.isPrivateOrLocalHost('photos.example.com'), isFalse);
      expect(HomeSpaceTlsTrust.isPrivateOrLocalHost('8.8.8.8'), isFalse);

      await HomeSpaceTlsTrust.initFromDirectory(tempDir);
      const fakeDigest = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      await HomeSpaceTlsTrust.trustCertificate(
        host: 'nas.home.arpa',
        port: 8443,
        sha256Hex: fakeDigest,
      );

      expect(HomeSpaceTlsTrust.pinFor('nas.home.arpa', 8443), fakeDigest);
      expect(HomeSpaceTlsTrust.pinFor('untrusted.example.com', 443), isNull);

      final storeFile = File('${tempDir.path}/trusted_certs.json');
      expect(storeFile.existsSync(), isTrue);
      final persisted = jsonDecode(storeFile.readAsStringSync()) as Map<String, dynamic>;
      expect(persisted['nas.home.arpa:8443'], fakeDigest);

      await HomeSpaceTlsTrust.initFromDirectory(tempDir);
      expect(HomeSpaceTlsTrust.pinFor('nas.home.arpa', 8443), fakeDigest);
    });

    test('SnapshotCodec.decode denies implicit admin privileges for non-Maya profiles', () {
      final payload = jsonEncode({
        'schemaVersion': SnapshotCodec.version,
        'media': [],
        'albums': [],
        'favorites': [],
        'trash': [],
        'family': [
          {'id': 'user-alice', 'name': 'Alice'},
        ],
        'profile': {
          'userId': 'user-bob',
          'name': 'Bob',
          'appearance': 'system',
          'avatarTone': 'blue',
        },
      });

      final decoded = SnapshotCodec.decode(payload);
      expect(decoded.profile.userId, 'user-bob');
      expect(decoded.profile.isAdmin, isFalse);

      final legacyMaya = jsonEncode({
        'schemaVersion': SnapshotCodec.version,
        'media': [],
        'albums': [],
        'favorites': [],
        'trash': [],
        'family': [],
        'profile': {
          'userId': 'member-maya',
          'name': 'Maya',
          'appearance': 'system',
          'avatarTone': 'green',
        },
      });
      expect(SnapshotCodec.decode(legacyMaya).profile.isAdmin, isTrue);
    });

    test('CacheService measures and clears managed cache directory', () async {
      final cacheDir = Directory.systemTemp.createTempSync('homespace_cache_test');
      CacheService.customCacheDir = cacheDir;
      addTearDown(() {
        CacheService.customCacheDir = null;
        if (cacheDir.existsSync()) {
          cacheDir.deleteSync(recursive: true);
        }
      });

      final nested = Directory('${cacheDir.path}/thumbs')..createSync(recursive: true);
      File('${cacheDir.path}/preview_1.webp').writeAsBytesSync(List<int>.filled(1024, 1));
      File('${nested.path}/thumb_2.webp').writeAsBytesSync(List<int>.filled(3072, 2));

      expect(await CacheService.getCacheSizeBytes(), 4096);
      final reclaimed = await CacheService.clearCache();
      expect(reclaimed, 4096);
      expect(await CacheService.getCacheSizeBytes(), 0);
    });

    test('LocalHomeRepository syncWithServer paginates media, syncs favorites & shared members, and avoids memberById crash', () async {
      final seenRequests = <String>[];
      final mockClient = MockClient((request) async {
        seenRequests.add('${request.url.path}?${request.url.query}');
        if (request.url.path == '/api/media') {
          final offset = int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
          if (offset == 0) {
            return http.Response(
              jsonEncode({
                'items': List.generate(
                  200,
                  (i) => {
                    'id': 'remote-$i',
                    'filename': 'photo_$i.jpg',
                    'kind': 'photo',
                    'takenAt': '2026-11-20T10:00:00.000Z',
                    'size': 2048,
                    'mimeType': 'image/jpeg',
                    'isFavorite': i == 1,
                  },
                ),
                'total': 201,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'remote-200',
                  'filename': 'photo_200.jpg',
                  'kind': 'photo',
                  'takenAt': '2026-11-21T10:00:00.000Z',
                  'size': 4096,
                  'mimeType': 'image/jpeg',
                  'isFavorite': true,
                },
              ],
              'total': 201,
            }),
            200,
          );
        }
        if (request.url.path == '/api/trash') {
          return http.Response(jsonEncode({'items': []}), 200);
        }
        if (request.url.path == '/api/albums') {
          return http.Response(
            jsonEncode({
              'albums': [
                {
                  'id': 'album-shared-1',
                  'userId': 'user-alice',
                  'title': 'Holiday',
                  'description': 'Trips',
                  'coverMediaId': 'remote-shared-1',
                  'isShared': true,
                  'mediaIds': ['remote-shared-1'],
                  'memberships': [
                    {'userId': 'user-alice', 'name': 'Alice', 'role': 'owner'},
                    {'userId': 'user-me-1', 'name': 'Sam', 'role': 'contributor'},
                  ],
                  'media': [
                    {
                      'id': 'remote-shared-1',
                      'userId': 'user-alice',
                      'filename': 'shared.jpg',
                      'kind': 'photo',
                      'takenAt': '2026-11-20T12:00:00.000Z',
                      'size': 8192,
                      'mimeType': 'image/jpeg',
                    },
                  ],
                  'createdAt': '2026-11-20T10:00:00.000Z',
                  'updatedAt': '2026-11-20T10:00:00.000Z',
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/family/members') {
          return http.Response(
            jsonEncode({
              'members': [
                {'id': 'user-alice', 'name': 'Alice'},
                {'id': 'user-me-1', 'name': 'Sam'},
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final repo = LocalHomeRepository(
        store: MemorySnapshotStore(),
        apiClient: HomeSpaceApiClient(client: mockClient),
      );
      addTearDown(repo.dispose);
      await repo.initialize();

      // Unknown member fallback returns placeholder instead of throwing StateError
      final unknown = repo.memberById('remote-stranger');
      expect(unknown.id, 'remote-stranger');
      expect(unknown.name, 'Family Member');

      await repo.initForAuthenticatedUser(
        userId: 'user-me-1',
        name: 'Sam',
        avatarTone: AvatarTone.green,
        isAdmin: false,
        clearDemoSeed: true,
      );
      expect(repo.media, isEmpty);
      expect(repo.albums, isEmpty);
      expect(repo.profile.isAdmin, isFalse);

      // Seed one stale synced item that was deleted remotely
      await repo.addMedia(
        MediaItem(
          id: 'stale-remote-id',
          asset: 'http://127.0.0.1:8888/api/media/stale-remote-id/file',
          title: 'stale.jpg',
          category: 'Camera',
          takenAt: DateTime.utc(2026, 11, 1),
          kind: MediaKind.photo,
          isSynced: true,
        ),
      );

      await repo.syncWithServer(
        serverUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'real-bearer-token',
      );

      expect(seenRequests.any((r) => r.contains('offset=0')), isTrue);
      expect(seenRequests.any((r) => r.contains('offset=200')), isTrue);
      expect(repo.media.any((m) => m.id == 'stale-remote-id'), isFalse);
      expect(repo.media.length, 202); // 201 paginated + 1 shared album photo
      expect(repo.favorites.contains('remote-1'), isTrue);
      expect(repo.favorites.contains('remote-200'), isTrue);
      expect(repo.memberById('user-alice').name, 'Alice');
    });

    testWidgets('AuthPage rejects HTTP 403 server errors without bypassing to Local Mode', (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = LocalHomeRepository(store: MemorySnapshotStore());
      final session = FrontendSession(
        serverUri: Uri.parse('https://example.com:8443'),
      );
      addTearDown(repo.dispose);
      addTearDown(session.dispose);
      await repo.initialize();

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'FORBIDDEN', 'message': 'Account disabled'},
          }),
          403,
        );
      });

      await tester.pumpWidget(
        HomeScope(
          repository: repo,
          child: MaterialApp(
            theme: spaceTheme(Brightness.light, SpacePage.profile),
            home: AuthPage(
              session: session,
              apiClientFactory: () => HomeSpaceApiClient(client: mockClient),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('auth-Email')), 'user@example.com');
      await tester.enterText(find.byKey(const ValueKey('auth-Password')), 'secret123');
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();

      expect(session.isAuthenticated, isFalse);
      expect(find.text('Account disabled'), findsOneWidget);
      expect(find.byType(AuthPage), findsOneWidget);
    });

    testWidgets('TrashPage skips orphaned trash entries without throwing', (tester) async {
      final repo = _OrphanTrashRepository(store: MemorySnapshotStore());
      addTearDown(repo.dispose);
      await repo.initialize();

      await tester.pumpWidget(
        HomeScope(
          repository: repo,
          child: const MaterialApp(
            home: TrashPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('AppLockPage stores salted hashed PIN and requires current PIN to disable or change', (tester) async {
      final repo = LocalHomeRepository(store: MemorySnapshotStore());
      addTearDown(repo.dispose);
      await repo.initialize();
      await repo.setAppLock(enabled: true, pin: '4242');

      expect(repo.profile.appLockEnabled, isTrue);
      expect(PinSecurity.isHashed(repo.profile.appLockPin), isTrue);
      expect(repo.profile.appLockPin, isNot('4242'));
      expect(PinSecurity.verifyPin('4242', repo.profile.appLockPin), isTrue);

      await tester.pumpWidget(
        HomeScope(
          repository: repo,
          child: MaterialApp(
            theme: spaceTheme(Brightness.light, SpacePage.profile),
            home: AppLockPage(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Changing PIN requires verifying current PIN first
      await tester.tap(find.byKey(const ValueKey('change-pin-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Verify Current PIN'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Disabling App Lock prompts current PIN verification
      await tester.tap(find.byKey(const ValueKey('app-lock-switch')));
      await tester.pumpAndSettle();
      expect(find.text('Verify PIN to Disable'), findsOneWidget);

      // Wrong PIN stays locked and reports error
      await tester.enterText(find.byKey(const ValueKey('verify-current-pin-field')), '0000');
      await tester.tap(find.byKey(const ValueKey('verify-pin-submit-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Incorrect PIN'), findsOneWidget);
      expect(repo.profile.appLockEnabled, isTrue);

      // Correct PIN unlocks disable action
      await tester.enterText(find.byKey(const ValueKey('verify-current-pin-field')), '4242');
      await tester.tap(find.byKey(const ValueKey('verify-pin-submit-btn')));
      await tester.pumpAndSettle();
      expect(repo.profile.appLockEnabled, isFalse);
    });
  });
}
