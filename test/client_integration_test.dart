import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:homespace/data/homespace_api_client.dart';
import 'package:homespace/data/http_remote_repositories.dart';
import 'package:homespace/domain/models.dart';

void main() {
  group('HomeSpaceApiClient Authentication', () {
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
    test('queueUpload saves locally and completes', () async {
      MediaItem? savedItem;
      final repo = HttpUploadRepository(
        onMediaUploaded: (item, _) {
          savedItem = item;
        },
      );

      repo.queueUpload(
        id: 'upload-1',
        mediaId: 'm-1',
        totalBytes: 500,
        bytes: [1, 2, 3],
        filename: 'test.jpg',
      );

      expect(repo.items.length, 1);
      // Wait for async local save
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repo.items.first.phase, UploadPhase.completed);
      expect(repo.items.first.bytesSent, 500);
      expect(repo.items.first.progress, 1.0);
      expect(savedItem, isNotNull);
      expect(savedItem!.title, 'test.jpg');
    });

    test('queueUpload preserves phone capture date into MediaItem', () async {
      MediaItem? receivedItem;
      final expectedDate = DateTime.utc(2022, 12, 25, 9, 15, 0);

      final repo = HttpUploadRepository(
        onMediaUploaded: (item, _) {
          receivedItem = item;
        },
      );

      repo.queueUpload(
        id: 'upload-date-test',
        mediaId: 'm-date',
        totalBytes: 500,
        bytes: [1, 2, 3],
        filename: 'xmas.jpg',
        takenAt: expectedDate,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repo.items.first.phase, UploadPhase.completed);
      expect(receivedItem, isNotNull);
      expect(receivedItem!.takenAt, expectedDate);
    });

    test('pause, resume, and cancel work as expected', () {
      final repo = HttpUploadRepository();

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

    test('clearCompleted cleans up completed uploads', () async {
      final repo = HttpUploadRepository();

      repo.queueUpload(
        id: 'upload-clear-test',
        mediaId: 'm-clear',
        totalBytes: 500,
        bytes: [1, 2, 3],
        filename: 'clear.jpg',
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repo.items.first.phase, UploadPhase.completed);

      repo.clearCompleted();
      expect(repo.items, isEmpty);
    });
  });

  group('Chunked upload client', () {
    test('uploadMediaFile chunks large files and reports real progress', () async {
      final tempDir = await Directory.systemTemp.createTemp('homespace_chunk_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final testFile = File('${tempDir.path}/video.mp4');
      final payload = List<int>.generate(25, (i) => i);
      await testFile.writeAsBytes(payload);

      final receivedOffsets = <int>[];
      final receivedBytes = <int>[];
      var initCalled = false;
      var completeCalled = false;

      final mockClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/api/media/upload/init') {
          initCalled = true;
          return http.Response(
            jsonEncode({
              'uploadId': 'up_test_123',
              'bytesReceived': 0,
              'totalBytes': payload.length,
              'chunkSize': 10,
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'PUT' &&
            request.url.path == '/api/media/upload/up_test_123/chunk') {
          final offset = int.parse(request.url.queryParameters['offset']!);
          receivedOffsets.add(offset);
          receivedBytes.addAll(request.bodyBytes);
          return http.Response(
            jsonEncode({
              'uploadId': 'up_test_123',
              'bytesReceived': offset + request.bodyBytes.length,
              'totalBytes': payload.length,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/media/upload/up_test_123/complete') {
          completeCalled = true;
          return http.Response(
            jsonEncode({
              'media': {
                'id': 'm_video_1',
                'filename': 'video.mp4',
                'kind': 'video',
                'size': payload.length,
                'mimeType': 'video/mp4',
                'takenAt': '2026-11-27T10:00:00.000Z',
              },
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final client = HomeSpaceApiClient(client: mockClient);
      final progressEvents = <int>[];
      final result = await client.uploadMediaFile(
        baseUri: Uri.parse('http://192.168.0.108:8888'),
        token: 'tok',
        filePath: testFile.path,
        filename: 'video.mp4',
        mimeType: 'video/mp4',
        chunkThresholdBytes: 10,
        onProgress: (sent, total) {
          progressEvents.add(sent);
        },
      );

      expect(initCalled, isTrue);
      expect(completeCalled, isTrue);
      expect(receivedOffsets, [0, 10, 20]);
      expect(receivedBytes, payload);
      expect(progressEvents.last, payload.length);
      expect(result.id, 'm_video_1');
      expect(result.kind, MediaKind.video);
    });

    test('cancelChunkedUpload sends DELETE to upload session', () async {
      var deletedPath = '';
      final mockClient = MockClient((request) async {
        if (request.method == 'DELETE') {
          deletedPath = request.url.path;
          return http.Response(
            jsonEncode({'canceled': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final client = HomeSpaceApiClient(client: mockClient);
      await client.cancelChunkedUpload(
        baseUri: Uri.parse('http://192.168.0.108:8888'),
        token: 'tok',
        uploadId: 'up_cancel_99',
      );
      expect(deletedPath, '/api/media/upload/up_cancel_99');
    });
  });
}
