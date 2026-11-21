import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homespace/data/homespace_api_client.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Media Remote Pipeline & Sync Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('homespace_remote_test_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('HomeSpaceApiClient fetchMedia parses timeline list', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/media');
        expect(request.headers['Authorization'], 'Bearer test_token');
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'm_001',
                'filename': 'IMG_20261121_01.jpg',
                'mimeType': 'image/jpeg',
                'size': 1024,
                'takenAt': '2026-11-21T10:00:00.000Z',
                'kind': 'photo',
                'isFavorite': false,
              },
              {
                'id': 'm_002',
                'filename': 'VID_20261121_02.mp4',
                'mimeType': 'video/mp4',
                'size': 2048,
                'takenAt': '2026-11-21T11:00:00.000Z',
                'kind': 'video',
                'isFavorite': true,
              }
            ],
            'total': 2,
          }),
          200,
        );
      });

      final apiClient = HomeSpaceApiClient(client: mockClient);
      final items = await apiClient.fetchMedia(
        baseUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'test_token',
      );

      expect(items.length, 2);
      expect(items[0].id, 'm_001');
      expect(items[0].title, 'IMG_20261121_01.jpg');
      expect(items[0].kind, MediaKind.photo);
      expect(items[0].isSynced, isTrue);

      expect(items[1].id, 'm_002');
      expect(items[1].title, 'VID_20261121_02.mp4');
      expect(items[1].kind, MediaKind.video);
      expect(items[1].isSynced, isTrue);
    });

    test('HomeSpaceApiClient uploadMediaFile uploads file via multipart', () async {
      final sampleFile = File('${tempDir.path}/test_upload.jpg');
      sampleFile.writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);

      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/media/upload');
        expect(request.headers['Authorization'], 'Bearer test_token');
        return http.Response(
          jsonEncode({
            'media': {
              'id': 'm_new_999',
              'filename': 'test_upload.jpg',
              'mimeType': 'image/jpeg',
              'size': 8,
              'takenAt': '2026-11-21T12:00:00.000Z',
              'kind': 'photo',
            }
          }),
          201,
        );
      });

      final apiClient = HomeSpaceApiClient(client: mockClient);
      final media = await apiClient.uploadMediaFile(
        baseUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'test_token',
        filePath: sampleFile.path,
        filename: 'test_upload.jpg',
        takenAt: DateTime.utc(2026, 11, 21, 12, 0, 0),
      );

      expect(media.id, 'm_new_999');
      expect(media.title, 'test_upload.jpg');
      expect(media.isSynced, isTrue);
      expect(media.asset, sampleFile.path);
    });

    test('LocalHomeRepository syncWithServer marks local matching photos isSynced', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'm_synced_photo',
                'filename': 'p1.jpg',
                'mimeType': 'image/jpeg',
                'size': 1234,
                'takenAt': '2026-11-21T10:00:00.000Z',
                'kind': 'photo',
              },
              {
                'id': 'm_remote_only',
                'filename': 'remote_snapshot.jpg',
                'mimeType': 'image/jpeg',
                'size': 5678,
                'takenAt': '2026-11-21T10:30:00.000Z',
                'kind': 'photo',
              }
            ],
            'total': 2,
          }),
          200,
        );
      });

      final apiClient = HomeSpaceApiClient(client: mockClient);
      final repo = LocalHomeRepository(
        store: MemorySnapshotStore(),
        apiClient: apiClient,
        scenario: DemoScenario.populated,
      );
      await repo.initialize();
      await repo.clearUserData();

      // Add a local un-synced photo with title 'p1.jpg'
      await repo.addMedia(MediaItem(
        id: 'local_p1',
        asset: 'assets/photos/p1.jpg',
        title: 'p1.jpg',
        category: 'Camera',
        takenAt: DateTime(2026, 11, 21, 10, 0),
        isSynced: false,
      ));

      expect(repo.media.first.isSynced, isFalse);

      // Sync with server
      await repo.syncWithServer(
        serverUri: Uri.parse('http://127.0.0.1:8888'),
        token: 'auth_token_xyz',
      );

      // Verify local photo p1 is now marked isSynced: true
      final p1 = repo.media.firstWhere((m) => m.title == 'p1.jpg');
      expect(p1.isSynced, isTrue);

      // Verify remote photo was also added to media feed
      final remotePhoto = repo.media.firstWhere((m) => m.id == 'm_remote_only');
      expect(remotePhoto.title, 'remote_snapshot.jpg');
      expect(remotePhoto.isSynced, isTrue);
    });
  });
}
