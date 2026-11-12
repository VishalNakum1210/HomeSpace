import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/application/frontend_session.dart';
import 'package:homespace/data/homespace_api_client.dart';
import 'package:homespace/domain/models.dart';
import 'package:http/testing.dart';

void main() {
  group('SessionStore and FrontendSession', () {
    test('Default session is unauthenticated and closed', () {
      final session = FrontendSession();
      expect(session.isOpen, isFalse);
      expect(session.isAuthenticated, isFalse);
      expect(session.authToken, isNull);
      expect(session.userId, isNull);
    });

    test('Session persists authentication and restores across restarts', () async {
      final store = MemorySessionStore();
      final initialSession = FrontendSession(
        serverUri: Uri.parse('https://custom.homeserver.local:8443'),
        store: store,
      );

      // 1. Initial restore has no data
      final restored1 = await initialSession.restoreSession();
      expect(restored1, isFalse);
      expect(initialSession.isOpen, isFalse);
      expect(initialSession.isAuthenticated, isFalse);

      // 2. User logs in
      var notified = false;
      initialSession.addListener(() => notified = true);

      await initialSession.setAuthenticated(
        serverUri: Uri.parse('https://custom.homeserver.local:8443'),
        token: 'sample-jwt-token-12345',
        userId: 'user-uuid-9876',
        email: 'test@homespace.local',
        name: 'Vishal',
        avatarTone: AvatarTone.orange,
      );

      expect(notified, isTrue);
      expect(initialSession.isOpen, isTrue);
      expect(initialSession.isAuthenticated, isTrue);
      expect(initialSession.authToken, 'sample-jwt-token-12345');
      expect(initialSession.userName, 'Vishal');

      // 3. New app launch with fresh FrontendSession reading same store
      final nextSession = FrontendSession(store: store);
      final restored2 = await nextSession.restoreSession();

      expect(restored2, isTrue);
      expect(nextSession.isOpen, isTrue);
      expect(nextSession.isAuthenticated, isTrue);
      expect(nextSession.authToken, 'sample-jwt-token-12345');
      expect(nextSession.userId, 'user-uuid-9876');
      expect(nextSession.userEmail, 'test@homespace.local');
      expect(nextSession.userName, 'Vishal');
      expect(nextSession.avatarTone, AvatarTone.orange);
      expect(nextSession.serverUri, Uri.parse('https://custom.homeserver.local:8443'));

      // 4. Update server URI
      await nextSession.updateServerUri(Uri.parse('https://updated.homeserver.local:8888'));
      expect(nextSession.serverUri, Uri.parse('https://updated.homeserver.local:8888'));

      final freshSessionAfterUpdate = FrontendSession(store: store);
      await freshSessionAfterUpdate.restoreSession();
      expect(freshSessionAfterUpdate.serverUri, Uri.parse('https://updated.homeserver.local:8888'));

      // 5. User logs out
      await nextSession.logout();
      expect(nextSession.isOpen, isFalse);
      expect(nextSession.isAuthenticated, isFalse);
      expect(nextSession.authToken, isNull);
      expect(nextSession.userId, isNull);

      // 6. Verify store is cleared on logout
      final sessionAfterLogout = FrontendSession(store: store);
      final restored3 = await sessionAfterLogout.restoreSession();
      expect(restored3, isFalse);
      expect(sessionAfterLogout.isOpen, isFalse);
    });

    test('FileSessionStore safely handles non-existent or corrupted files', () async {
      final tempDir = await Directory.systemTemp.createTemp('homespace_test_session');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final store = FileSessionStore(() async => tempDir);
      expect(await store.loadSession(), isNull);

      await store.saveSession({'token': 'token-abc', 'userId': 'uid-1'});
      final loaded = await store.loadSession();
      expect(loaded?['token'], 'token-abc');

      // Corrupt file
      final file = File('${tempDir.path}/session.json');
      await file.writeAsString('{not valid json');
      expect(await store.loadSession(), isNull);

      await store.clearSession();
      expect(await file.exists(), isFalse);
    });
  });

  group('HomeSpaceApiClient TLS and error handling', () {
    test('Translates HandshakeException into user-friendly HomeSpaceServerException', () async {
      final mockClient = MockClient((request) async {
        throw const HandshakeException('CERTIFICATE_VERIFY_FAILED: certificate has expired');
      });

      final client = HomeSpaceApiClient(client: mockClient);

      expect(
        () => client.login(
          baseUri: Uri.parse('https://test.server'),
          email: 'test@example.com',
          password: 'password123',
        ),
        throwsA(
          isA<HomeSpaceServerException>()
              .having((e) => e.code, 'code', 'TLS_HANDSHAKE_FAILED')
              .having((e) => e.message, 'message', contains('Secure SSL/TLS handshake failed')),
        ),
      );
    });

    test('Translates SocketException into SERVER_UNREACHABLE', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('Connection refused');
      });

      final client = HomeSpaceApiClient(client: mockClient);

      expect(
        () => client.login(
          baseUri: Uri.parse('https://test.server'),
          email: 'test@example.com',
          password: 'password123',
        ),
        throwsA(
          isA<HomeSpaceServerException>()
              .having((e) => e.code, 'code', 'SERVER_UNREACHABLE')
              .having((e) => e.message, 'message', contains('Cannot reach home server')),
        ),
      );
    });
  });
}
