import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homespace/application/home_scope.dart';
import 'package:homespace/data/homespace_api_client.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/pages/trash_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 6: Trash Remote Pipeline & Sync Tests', () {
    test('HomeSpaceApiClient fetchTrash queries correctly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/trash');
        expect(request.headers['Authorization'], 'Bearer test_token');
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'm-trashed-1',
                'filename': 'old_photo.jpg',
                'mimeType': 'image/jpeg',
                'size': 1024,
                'takenAt': '2026-11-20T10:00:00.000Z',
                'kind': 'photo',
                'isFavorite': false,
                'isTrashed': true,
                'trashedAt': '2026-11-21T10:00:00.000Z',
                'isSynced': true,
              },
            ],
            'total': 1,
          }),
          200,
        );
      });

      final apiClient = HomeSpaceApiClient(client: mockClient);
      final trashed = await apiClient.fetchTrash(
        baseUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'test_token',
      );

      expect(trashed.length, 1);
      expect(trashed[0].id, 'm-trashed-1');
      expect(trashed[0].title, 'old_photo.jpg');
    });

    test('HomeSpaceApiClient emptyTrash posts to /api/trash/empty', () async {
      bool called = false;
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/trash/empty');
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer test_token');
        called = true;
        return http.Response(
          jsonEncode({'success': true, 'count': 3, 'freedBytes': 3072}),
          200,
        );
      });

      final apiClient = HomeSpaceApiClient(client: mockClient);
      await apiClient.emptyTrash(
        baseUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'test_token',
      );

      expect(called, isTrue);
    });

    test('LocalHomeRepository syncWithServer reconciles remote trashed media', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/trash') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'm-remote-trashed',
                  'filename': 'trashed_remote.jpg',
                  'mimeType': 'image/jpeg',
                  'size': 2048,
                  'takenAt': '2026-11-20T10:00:00.000Z',
                  'kind': 'photo',
                  'isFavorite': false,
                  'isTrashed': true,
                  'trashedAt': '2026-11-21T10:00:00.000Z',
                },
              ],
              'total': 1,
            }),
            200,
          );
        } else if (request.url.path == '/api/media') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'm-active-1',
                  'filename': 'active.jpg',
                  'mimeType': 'image/jpeg',
                  'size': 1024,
                  'takenAt': '2026-11-20T10:00:00.000Z',
                  'kind': 'photo',
                  'isFavorite': false,
                  'isTrashed': false,
                },
              ],
              'total': 1,
            }),
            200,
          );
        } else if (request.url.path == '/api/albums') {
          return http.Response(
            jsonEncode({'albums': [], 'total': 0}),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final store = MemorySnapshotStore();
      final repository = LocalHomeRepository(store: store);
      addTearDown(repository.dispose);
      await repository.initialize();

      await repository.syncWithServer(
        serverUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'test_token',
        apiClient: HomeSpaceApiClient(client: mockClient),
      );

      // Verify active media contains m-active-1 and does NOT include m-remote-trashed in public feed
      expect(repository.media.any((m) => m.id == 'm-active-1'), isTrue);
      expect(repository.media.any((m) => m.id == 'm-remote-trashed'), isFalse);

      // Verify trash contains m-remote-trashed
      expect(repository.trash.any((t) => t.mediaId == 'm-remote-trashed'), isTrue);
    });
  });

  group('Phase 6: TrashPage UI Tests', () {
    testWidgets('TrashPage shows retention message and remaining days countdown', (tester) async {
      final store = MemorySnapshotStore();
      final repository = LocalHomeRepository(store: store);
      addTearDown(repository.dispose);
      await repository.initialize();

      // Move a media item to trash
      await repository.moveManyToTrash(['media-01']);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScope(
            repository: repository,
            child: const TrashPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check retention policy message
      expect(find.text('Items are permanently deleted after 30 days.'), findsOneWidget);

      // Check remaining days countdown badge
      expect(find.text('30 days remaining'), findsOneWidget);

      // Check empty trash button is visible
      expect(find.byKey(const ValueKey('empty-trash')), findsOneWidget);
    });

    testWidgets('TrashPage selection mode restores selected items', (tester) async {
      final store = MemorySnapshotStore();
      final repository = LocalHomeRepository(store: store);
      addTearDown(repository.dispose);
      await repository.initialize();

      await repository.moveManyToTrash(['media-01', 'media-02']);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScope(
            repository: repository,
            child: const TrashPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.trash.length, 2);

      // Long press first item to start selection
      await tester.longPress(find.byKey(const ValueKey('trash-media-01')));
      await tester.pumpAndSettle();

      // Tap restore
      await tester.tap(find.byKey(const ValueKey('restore-selected')));
      await tester.pumpAndSettle();

      // media-01 should be restored, media-02 remains in trash
      expect(repository.trash.map((t) => t.mediaId), contains('media-02'));
      expect(repository.trash.map((t) => t.mediaId), isNot(contains('media-01')));
      expect(repository.media.any((m) => m.id == 'media-01'), isTrue);
    });
  });
}
