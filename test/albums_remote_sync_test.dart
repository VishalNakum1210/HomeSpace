import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homespace/data/homespace_api_client.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Albums Remote Pipeline & Sync Tests', () {
    test('HomeSpaceApiClient fetchAlbums parses albums correctly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/albums');
        expect(request.headers['Authorization'], 'Bearer test_token');
        return http.Response(
          jsonEncode({
            'albums': [
              {
                'id': 'album-001',
                'userId': 'user-123',
                'title': 'Summer Beach',
                'description': 'Sunny days',
                'coverMediaId': 'm-1',
                'isShared': false,
                'mediaCount': 2,
                'mediaIds': ['m-1', 'm-2'],
                'createdAt': '2026-11-21T10:00:00.000Z',
                'updatedAt': '2026-11-21T10:00:00.000Z',
              },
            ],
            'total': 1,
          }),
          200,
        );
      });

      final apiClient = HomeSpaceApiClient(client: mockClient);
      final albums = await apiClient.fetchAlbums(
        baseUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'test_token',
        currentUserId: 'user-123',
      );

      expect(albums.length, 1);
      expect(albums[0].id, 'album-001');
      expect(albums[0].title, 'Summer Beach');
      expect(albums[0].description, 'Sunny days');
      expect(albums[0].mediaIds, ['m-1', 'm-2']);
      expect(albums[0].coverId, 'm-1');
      expect(albums[0].shared, isFalse);
    });

    test('HomeSpaceApiClient createRemoteAlbum posts album data and parses created album', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/albums');
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['title'], 'New Adventure');
        expect(body['mediaIds'], ['m-1', 'm-2']);
        return http.Response(
          jsonEncode({
            'album': {
              'id': 'album-new-99',
              'userId': 'user-123',
              'title': 'New Adventure',
              'description': '',
              'coverMediaId': 'm-1',
              'isShared': false,
              'mediaCount': 2,
              'mediaIds': ['m-1', 'm-2'],
              'createdAt': '2026-11-21T12:00:00.000Z',
              'updatedAt': '2026-11-21T12:00:00.000Z',
            }
          }),
          201,
        );
      });

      final apiClient = HomeSpaceApiClient(client: mockClient);
      final album = await apiClient.createRemoteAlbum(
        baseUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'test_token',
        title: 'New Adventure',
        mediaIds: ['m-1', 'm-2'],
        currentUserId: 'user-123',
      );

      expect(album.id, 'album-new-99');
      expect(album.title, 'New Adventure');
      expect(album.mediaIds, ['m-1', 'm-2']);
      expect(album.coverId, 'm-1');
    });

    test('HomeSpaceApiClient updateRemoteAlbum sends PATCH', () async {
      bool patchCalled = false;
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/albums/album-001');
        expect(request.method, 'PATCH');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['title'], 'Renamed Album');
        patchCalled = true;
        return http.Response(jsonEncode({'success': true}), 200);
      });

      final apiClient = HomeSpaceApiClient(client: mockClient);
      await apiClient.updateRemoteAlbum(
        baseUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'test_token',
        albumId: 'album-001',
        title: 'Renamed Album',
      );

      expect(patchCalled, isTrue);
    });

    test('HomeSpaceApiClient addMediaToRemoteAlbum & removeMediaFromRemoteAlbum', () async {
      bool addCalled = false;
      bool removeCalled = false;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/albums/album-001/media') {
          expect(request.method, 'POST');
          final body = jsonDecode(request.body);
          expect(body['mediaIds'], ['m-3']);
          addCalled = true;
          return http.Response(jsonEncode({'success': true, 'count': 1}), 200);
        } else if (request.url.path == '/api/albums/album-001/media/remove') {
          expect(request.method, 'POST');
          final body = jsonDecode(request.body);
          expect(body['mediaIds'], ['m-3']);
          removeCalled = true;
          return http.Response(jsonEncode({'success': true, 'count': 1}), 200);
        }
        return http.Response('Not found', 404);
      });

      final apiClient = HomeSpaceApiClient(client: mockClient);
      await apiClient.addMediaToRemoteAlbum(
        baseUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'test_token',
        albumId: 'album-001',
        mediaIds: ['m-3'],
      );
      await apiClient.removeMediaFromRemoteAlbum(
        baseUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'test_token',
        albumId: 'album-001',
        mediaIds: ['m-3'],
      );

      expect(addCalled, isTrue);
      expect(removeCalled, isTrue);
    });

    test('HomeSpaceApiClient deleteRemoteAlbum sends DELETE', () async {
      bool deleteCalled = false;
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/albums/album-001');
        expect(request.method, 'DELETE');
        deleteCalled = true;
        return http.Response(jsonEncode({'success': true, 'deletedId': 'album-001'}), 200);
      });

      final apiClient = HomeSpaceApiClient(client: mockClient);
      await apiClient.deleteRemoteAlbum(
        baseUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'test_token',
        albumId: 'album-001',
      );

      expect(deleteCalled, isTrue);
    });

    test('LocalHomeRepository syncWithServer reconciles remote albums with local state', () async {
      final store = MemorySnapshotStore();
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/media') {
          return http.Response(jsonEncode({'items': [], 'total': 0}), 200);
        }
        if (request.url.path == '/api/albums') {
          return http.Response(
            jsonEncode({
              'albums': [
                {
                  'id': 'remote-album-100',
                  'userId': 'member-maya',
                  'title': 'Remote Sunset',
                  'description': 'From laptop server',
                  'coverMediaId': 'media-01',
                  'isShared': false,
                  'mediaCount': 1,
                  'mediaIds': ['media-01'],
                  'createdAt': '2026-11-21T10:00:00.000Z',
                  'updatedAt': '2026-11-21T10:00:00.000Z',
                }
              ],
              'total': 1,
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = HomeSpaceApiClient(client: mockClient);
      final repo = LocalHomeRepository(
        store: store,
        getServerAddress: () => Uri.parse('http://127.0.0.1:8888'),
        getAuthToken: () => 'valid_token',
        apiClient: apiClient,
      );
      addTearDown(repo.dispose);
      await repo.initialize();

      expect(repo.albums.any((a) => a.id == 'remote-album-100'), isFalse);

      await repo.syncWithServer(
        serverUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'valid_token',
        apiClient: apiClient,
      );

      expect(repo.albums.any((a) => a.id == 'remote-album-100'), isTrue);
      final syncdAlbum = repo.albums.firstWhere((a) => a.id == 'remote-album-100');
      expect(syncdAlbum.title, 'Remote Sunset');
      expect(syncdAlbum.description, 'From laptop server');
      expect(syncdAlbum.mediaIds, ['media-01']);
    });
  });
}
