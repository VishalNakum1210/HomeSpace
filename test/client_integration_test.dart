import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:homespace/data/homespace_api_client.dart';
import 'package:homespace/data/http_remote_repositories.dart';
import 'package:homespace/domain/models.dart';

void main() {
  group('HomeSpaceApiClient', () {
    test('checkHealth returns true on 200 with service: homespace', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/health') {
          return http.Response(
            jsonEncode({'status': 'ok', 'service': 'homespace', 'version': '1.0.0'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final client = HomeSpaceApiClient(client: mockClient);
      final healthy = await client.checkHealth(Uri.parse('http://192.168.0.108:8888'));
      expect(healthy, isTrue);
    });

    test('register parses user, token and storage info', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/register') {
          return http.Response(
            jsonEncode({
              'token': 'mock_token_123',
              'user': {
                'id': 'u_alice',
                'email': 'alice@test.com',
                'name': 'Alice',
                'avatarTone': 'orange',
                'storageQuotaBytes': 10737418240,
                'storageUsedBytes': 0,
              },
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final client = HomeSpaceApiClient(client: mockClient);
      final result = await client.register(
        baseUri: Uri.parse('http://192.168.0.108:8888'),
        email: 'alice@test.com',
        password: 'password123',
        name: 'Alice',
      );

      expect(result.token, 'mock_token_123');
      expect(result.userId, 'u_alice');
      expect(result.email, 'alice@test.com');
      expect(result.name, 'Alice');
      expect(result.storageQuotaBytes, 10737418240);
      expect(result.storageUsedBytes, 0);
    });

    test('login parses token and profile correctly', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({
              'token': 'login_token_xyz',
              'user': {
                'id': 'u_alice',
                'email': 'alice@test.com',
                'name': 'Alice',
                'avatarTone': 'blue',
                'storageQuotaBytes': 10737418240,
                'storageUsedBytes': 500000,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final client = HomeSpaceApiClient(client: mockClient);
      final result = await client.login(
        baseUri: Uri.parse('http://192.168.0.108:8888'),
        email: 'alice@test.com',
        password: 'password123',
      );

      expect(result.token, 'login_token_xyz');
      expect(result.avatarTone, AvatarTone.blue);
      expect(result.storageUsedBytes, 500000);
    });

    test('fetchMedia parses items into strongly typed MediaItems', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/media') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'm_photo_1',
                  'userId': 'u_alice',
                  'fileName': 'vacation.jpg',
                  'mimeType': 'image/jpeg',
                  'byteSize': 123456,
                  'width': 1920,
                  'height': 1080,
                  'takenAt': '2026-11-12T10:00:00.000Z',
                  'createdAt': '2026-11-12T10:00:00.000Z',
                  'isFavorite': true,
                  'isTrashed': false,
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final client = HomeSpaceApiClient(client: mockClient);
      final items = await client.fetchMedia(
        Uri.parse('http://192.168.0.108:8888'),
        'token',
      );

      expect(items.length, 1);
      expect(items.first.id, 'm_photo_1');
      expect(items.first.title, 'vacation.jpg');
      expect(items.first.kind, MediaKind.photo);
      expect(
        items.first.asset,
        'http://192.168.0.108:8888/api/media/m_photo_1/thumb',
      );
    });

    test('fetchMedia identifies video items properly', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/media') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'm_video_1',
                  'userId': 'u_alice',
                  'fileName': 'clip.mp4',
                  'mimeType': 'video/mp4',
                  'byteSize': 5000000,
                  'width': 1920,
                  'height': 1080,
                  'takenAt': '2026-11-12T10:00:00.000Z',
                  'createdAt': '2026-11-12T10:00:00.000Z',
                  'isFavorite': false,
                  'isTrashed': false,
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final client = HomeSpaceApiClient(client: mockClient);
      final items = await client.fetchMedia(
        Uri.parse('http://192.168.0.108:8888'),
        'token',
      );

      expect(items.length, 1);
      expect(items.first.id, 'm_video_1');
      expect(items.first.title, 'clip.mp4');
      expect(items.first.kind, MediaKind.video);
    });

    test('throws HomeSpaceServerException on API error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'INVALID_CREDENTIALS',
              'message': 'Incorrect email or password.',
            },
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = HomeSpaceApiClient(client: mockClient);
      expect(
        () => client.login(
          baseUri: Uri.parse('http://192.168.0.108:8888'),
          email: 'wrong@test.com',
          password: 'wrong',
        ),
        throwsA(isA<HomeSpaceServerException>().having(
          (e) => e.code,
          'code',
          'INVALID_CREDENTIALS',
        )),
      );
    });
  });

  group('HttpConnectionRepository', () {
    test('connect updates status to connected on healthy server', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'ok', 'service': 'homespace'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final repo = HttpConnectionRepository(
        apiClient: HomeSpaceApiClient(client: mockClient),
      );

      final status = await repo.connect(Uri.parse('http://192.168.0.108:8888'));
      expect(status.phase, ConnectionPhase.connected);
      expect(status.isDemo, isFalse);

      repo.disconnect();
      expect(repo.status.phase, ConnectionPhase.disconnected);
    });

    test('connect updates status to failed on unreachable server', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network unreachable');
      });

      final repo = HttpConnectionRepository(
        apiClient: HomeSpaceApiClient(client: mockClient),
      );

      final status = await repo.connect(Uri.parse('http://192.168.0.108:8888'));
      expect(status.phase, ConnectionPhase.failed);
      expect(status.isDemo, isFalse);
    });
  });

  group('HttpUploadRepository', () {
    test('queueUpload tracks progress and status transitions', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 'm_up_1',
            'fileName': 'test.jpg',
            'takenAt': '2026-11-12T10:00:00.000Z',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final repo = HttpUploadRepository(
        apiClient: HomeSpaceApiClient(client: mockClient),
        getServerAddress: () => Uri.parse('http://192.168.0.108:8888'),
        getAuthToken: () => 'valid_token',
      );

      repo.queueUpload(
        id: 'upload-1',
        mediaId: 'm-1',
        totalBytes: 500,
        bytes: [1, 2, 3],
        filename: 'test.jpg',
      );

      expect(repo.items.length, 1);
      // Wait for async startUpload
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repo.items.first.phase, UploadPhase.completed);
      expect(repo.items.first.bytesSent, 500);
      expect(repo.items.first.progress, 1.0);
    });

    test('pause, resume, and cancel work as expected', () {
      final repo = HttpUploadRepository(
        getServerAddress: () => null,
        getAuthToken: () => null,
      );

      repo.queueUpload(
        id: 'upload-2',
        mediaId: 'm-2',
        totalBytes: 1000,
        bytes: [],
        filename: 'f.jpg',
      );

      repo.pause('upload-2');
      repo.resume('upload-2');
      repo.cancel('upload-2');
      expect(repo.items.first.phase, UploadPhase.canceled);
    });
  });
}
