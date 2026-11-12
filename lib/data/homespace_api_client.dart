import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../domain/models.dart';

class _MultipartRequestWithProgress extends http.MultipartRequest {
  final void Function(int bytesSent, int totalBytes)? onProgress;

  _MultipartRequestWithProgress(
    super.method,
    super.url, {
    this.onProgress,
  });

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    int sent = 0;

    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        sent += chunk.length;
        sink.add(chunk);
        if (onProgress != null && total > 0) {
          onProgress!(sent, total);
        }
      },
    );

    return http.ByteStream(byteStream.transform(transformer));
  }
}

class HomeSpaceServerException implements Exception {
  final String code;
  final String message;
  final int statusCode;

  const HomeSpaceServerException({
    required this.code,
    required this.message,
    required this.statusCode,
  });

  @override
  String toString() => '$message ($code)';
}

class HomeSpaceAuthResult {
  final String token;
  final String userId;
  final String email;
  final String name;
  final AvatarTone avatarTone;
  final int storageQuotaBytes;
  final int storageUsedBytes;

  const HomeSpaceAuthResult({
    required this.token,
    required this.userId,
    required this.email,
    required this.name,
    required this.avatarTone,
    required this.storageQuotaBytes,
    required this.storageUsedBytes,
  });
}

http.Client createHomeSpaceHttpClient() {
  final ioClient = HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) {
      // Allow connections to home servers over Tailscale Funnel, local LAN IPs, or self-signed certs
      return true;
    }
    ..connectionTimeout = const Duration(seconds: 15);
  return IOClient(ioClient);
}

class HomeSpaceApiClient {
  final http.Client _client;

  HomeSpaceApiClient({http.Client? client})
      : _client = client ?? createHomeSpaceHttpClient();

  void close() {
    _client.close();
  }

  Uri _resolve(Uri baseUri, String path, [Map<String, dynamic>? queryParameters]) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final basePath = baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
    return baseUri.replace(
      path: '$basePath$cleanPath',
      queryParameters: queryParameters?.map((k, v) => MapEntry(k, v.toString())),
    );
  }

  Map<String, String> _headers([String? token]) {
    final map = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      map['Authorization'] = 'Bearer $token';
    }
    return map;
  }

  Never _handleError(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is Map) {
        final err = body['error'];
        throw HomeSpaceServerException(
          code: err['code']?.toString() ?? 'ERROR',
          message: err['message']?.toString() ?? 'Server error',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is HomeSpaceServerException) rethrow;
    }
    throw HomeSpaceServerException(
      code: 'HTTP_${response.statusCode}',
      message: 'Server returned HTTP ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on HomeSpaceServerException {
      rethrow;
    } on HandshakeException catch (e) {
      throw HomeSpaceServerException(
        code: 'TLS_HANDSHAKE_FAILED',
        message:
            'Secure SSL/TLS handshake failed: ${e.message}. '
            'Please verify server address and check that Tailscale Funnel is online.',
        statusCode: 0,
      );
    } on TlsException catch (e) {
      throw HomeSpaceServerException(
        code: 'TLS_ERROR',
        message: 'TLS error: ${e.message}. Check your server address and certificate.',
        statusCode: 0,
      );
    } on SocketException catch (e) {
      throw HomeSpaceServerException(
        code: 'SERVER_UNREACHABLE',
        message:
            'Cannot reach home server (${e.osError?.message ?? e.message}). '
            'Please ensure the server laptop is awake and online.',
        statusCode: 0,
      );
    } on TimeoutException {
      throw const HomeSpaceServerException(
        code: 'TIMEOUT',
        message: 'Connection timed out. Check that your laptop server is awake and online.',
        statusCode: 0,
      );
    } on http.ClientException catch (e) {
      final msg = e.message;
      if (msg.contains('HandshakeException') || msg.contains('CERTIFICATE_VERIFY_FAILED')) {
        throw const HomeSpaceServerException(
          code: 'TLS_HANDSHAKE_FAILED',
          message: 'SSL certificate verification failed. Check server address or Tailscale Funnel.',
          statusCode: 0,
        );
      }
      throw HomeSpaceServerException(
        code: 'CLIENT_ERROR',
        message: 'Connection failed: ${e.message}',
        statusCode: 0,
      );
    } catch (e) {
      if (e is HomeSpaceServerException) rethrow;
      throw HomeSpaceServerException(
        code: 'NETWORK_ERROR',
        message: 'Network error: $e',
        statusCode: 0,
      );
    }
  }

  // 1. Health check
  Future<bool> checkHealth(Uri baseUri) async {
    final url = _resolve(baseUri, 'api/health');
    try {
      final response = await _client.get(
        url,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body is Map && body['service'] == 'homespace';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // 2. Register
  Future<HomeSpaceAuthResult> register({
    required Uri baseUri,
    required String email,
    required String password,
    required String name,
    AvatarTone avatarTone = AvatarTone.orange,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/auth/register');
    final response = await _client.post(
      url,
      headers: _headers(),
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'name': name.trim(),
        'avatarTone': avatarTone.name,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 201) _handleError(response);

    final data = jsonDecode(response.body);
    final user = data['user'] as Map<String, dynamic>;

    return HomeSpaceAuthResult(
      token: data['token'] as String,
      userId: user['id'] as String,
      email: user['email'] as String,
      name: user['name'] as String,
      avatarTone: AvatarTone.values.byName(user['avatarTone'] as String? ?? 'orange'),
      storageQuotaBytes: (user['storageQuotaBytes'] as num?)?.toInt() ?? 0,
      storageUsedBytes: (user['storageUsedBytes'] as num?)?.toInt() ?? 0,
    );
  });

  // 3. Login
  Future<HomeSpaceAuthResult> login({
    required Uri baseUri,
    required String email,
    required String password,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/auth/login');
    final response = await _client.post(
      url,
      headers: _headers(),
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);

    final data = jsonDecode(response.body);
    final user = data['user'] as Map<String, dynamic>;

    return HomeSpaceAuthResult(
      token: data['token'] as String,
      userId: user['id'] as String,
      email: user['email'] as String,
      name: user['name'] as String,
      avatarTone: AvatarTone.values.byName(user['avatarTone'] as String? ?? 'orange'),
      storageQuotaBytes: (user['storageQuotaBytes'] as num?)?.toInt() ?? 0,
      storageUsedBytes: (user['storageUsedBytes'] as num?)?.toInt() ?? 0,
    );
  });

  // 4. Fetch media items
  Future<List<MediaItem>> fetchMedia(Uri baseUri, String token, {bool trashed = false}) =>
      _guard(() async {
    final url = _resolve(baseUri, 'api/media', {'trashed': trashed ? '1' : '0'});
    final response = await _client.get(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);

    final data = jsonDecode(response.body);
    final items = (data['items'] as List<dynamic>?) ?? [];

    return items.map((raw) {
      final map = raw as Map<String, dynamic>;
      final id = map['id'] as String;
      final thumbUrl = _resolve(baseUri, 'api/media/$id/thumb').toString();
      final takenAtIso = map['takenAt'] as String? ?? map['createdAt'] as String;
      final mime = (map['mimeType'] as String?) ?? '';
      final fileName = (map['fileName'] as String?) ?? '';
      final lowerName = fileName.toLowerCase();
      final isVideo = mime.startsWith('video/') ||
          lowerName.endsWith('.mp4') ||
          lowerName.endsWith('.mov') ||
          lowerName.endsWith('.webm') ||
          lowerName.endsWith('.mkv') ||
          lowerName.endsWith('.3gp') ||
          lowerName.endsWith('.avi');

      return MediaItem(
        id: id,
        asset: thumbUrl,
        title: fileName.isNotEmpty ? fileName : (isVideo ? 'Video' : 'Photo'),
        category: 'Library',
        takenAt: DateTime.tryParse(takenAtIso) ?? DateTime.now(),
        kind: isVideo ? MediaKind.video : MediaKind.photo,
      );
    }).toList();
  });

  // 5. Upload media (Supports photos & videos with live progress tracking)
  Future<MediaItem> uploadMedia({
    required Uri baseUri,
    required String token,
    required List<int> fileBytes,
    required String filename,
    String? mimeType,
    DateTime? takenAt,
    void Function(int bytesSent, int totalBytes)? onProgress,
  }) => _guard(() async {
    final url = _resolve(
      baseUri,
      'api/media/upload',
      takenAt != null ? {'takenAt': takenAt.toUtc().toIso8601String()} : null,
    );
    final resolvedMime = mimeType ?? lookupMimeType(filename) ?? 'image/jpeg';
    MediaType? mediaType;
    try {
      mediaType = MediaType.parse(resolvedMime);
    } catch (_) {
      mediaType = MediaType('image', 'jpeg');
    }

    final request = _MultipartRequestWithProgress(
      'POST',
      url,
      onProgress: onProgress,
    )
      ..headers['Authorization'] = 'Bearer $token';

    if (takenAt != null) {
      final iso = takenAt.toUtc().toIso8601String();
      request.headers['x-taken-at'] = iso;
      request.fields['takenAt'] = iso;
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: filename,
        contentType: mediaType,
      ),
    );

    // Allow up to 10 minutes for large videos or slower mobile uploads
    final streamedResponse = await _client.send(request).timeout(const Duration(minutes: 10));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 201) _handleError(response);

    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final id = map['id'] as String;
    final thumbUrl = _resolve(baseUri, 'api/media/$id/thumb').toString();
    final takenAtIso = map['takenAt'] as String? ?? map['createdAt'] as String;
    final mime = map['mimeType'] as String? ?? resolvedMime;
    final isVideo = mime.startsWith('video/');

    return MediaItem(
      id: id,
      asset: thumbUrl,
      title: map['fileName'] as String? ?? filename,
      category: 'Uploads',
      takenAt: DateTime.tryParse(takenAtIso) ?? DateTime.now(),
      kind: isVideo ? MediaKind.video : MediaKind.photo,
    );
  });

  // 6. Favorite toggle
  Future<void> toggleFavorite(Uri baseUri, String token, String mediaId, bool favorite) =>
      _guard(() async {
    final url = _resolve(baseUri, 'api/media/$mediaId');
    final response = await _client.patch(
      url,
      headers: _headers(token),
      body: jsonEncode({'favorite': favorite}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _handleError(response);
  });

  // 7. Trash media
  Future<void> trashMedia(Uri baseUri, String token, String mediaId) =>
      _guard(() async {
    final url = _resolve(baseUri, 'api/media/$mediaId/trash');
    final response = await _client.post(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _handleError(response);
  });

  // 7b. Batch trash media
  Future<int> batchTrashMedia(Uri baseUri, String token, List<String> ids) =>
      _guard(() async {
    if (ids.isEmpty) return 0;
    final url = _resolve(baseUri, 'api/media/batch/trash');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({'ids': ids}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _handleError(response);
    final data = jsonDecode(response.body);
    return (data['trashedCount'] as num?)?.toInt() ?? 0;
  });

  // 8. Restore media
  Future<void> restoreMedia(Uri baseUri, String token, String mediaId) =>
      _guard(() async {
    final url = _resolve(baseUri, 'api/media/$mediaId/restore');
    final response = await _client.post(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _handleError(response);
  });

  // 8b. Batch restore media
  Future<int> batchRestoreMedia(Uri baseUri, String token, List<String> ids) =>
      _guard(() async {
    if (ids.isEmpty) return 0;
    final url = _resolve(baseUri, 'api/media/batch/restore');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({'ids': ids}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _handleError(response);
    final data = jsonDecode(response.body);
    return (data['restoredCount'] as num?)?.toInt() ?? 0;
  });

  // 9. Permanent delete
  Future<void> deleteMedia(Uri baseUri, String token, String mediaId) =>
      _guard(() async {
    final url = _resolve(baseUri, 'api/media/$mediaId');
    final response = await _client.delete(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _handleError(response);
  });

  // 9b. Batch delete media
  Future<int> batchDeleteMedia(Uri baseUri, String token, List<String> ids) =>
      _guard(() async {
    if (ids.isEmpty) return 0;
    final url = _resolve(baseUri, 'api/media/batch/delete');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({'ids': ids}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _handleError(response);
    final data = jsonDecode(response.body);
    return (data['deletedCount'] as num?)?.toInt() ?? 0;
  });

  // 9c. Batch favorite media
  Future<int> batchFavoriteMedia(Uri baseUri, String token, List<String> ids, bool favorite) =>
      _guard(() async {
    if (ids.isEmpty) return 0;
    final url = _resolve(baseUri, 'api/media/batch/favorite');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({'ids': ids, 'favorite': favorite}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _handleError(response);
    final data = jsonDecode(response.body);
    return (data['updatedCount'] as num?)?.toInt() ?? 0;
  });

  // 10. Fetch albums
  Future<List<Album>> fetchAlbums(Uri baseUri, String token) =>
      _guard(() async {
    final url = _resolve(baseUri, 'api/albums');
    final response = await _client.get(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);

    final data = jsonDecode(response.body);
    final albums = (data['albums'] as List<dynamic>?) ?? [];

    return albums.map<Album>((raw) {
      final map = raw as Map<String, dynamic>;
      final rawMedia = (map['mediaIds'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const <String>[];
      return Album(
        id: map['id'] as String,
        title: map['title'] as String,
        description: map['description'] as String? ?? '',
        coverId: map['coverMediaId'] as String?,
        mediaIds: rawMedia,
        memberships: [
          AlbumMembership(
            map['ownerId'] as String,
            AlbumRole.values.byName(map['userRole'] as String? ?? 'owner'),
          ),
        ],
        addedBy: const {},
      );
    }).toList();
  });

  // 11. Create album
  Future<String> createAlbum({
    required Uri baseUri,
    required String token,
    required String title,
    String description = '',
    List<String> mediaIds = const [],
    String? coverId,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/albums');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({
        'title': title,
        'description': description,
        'coverMediaId': coverId,
        'mediaIds': mediaIds,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 201) _handleError(response);
    final data = jsonDecode(response.body);
    return data['id'] as String;
  });

  // 12. Delete album
  Future<void> deleteAlbum(Uri baseUri, String token, String albumId) =>
      _guard(() async {
    final url = _resolve(baseUri, 'api/albums/$albumId');
    final response = await _client.delete(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _handleError(response);
  });

  // 13. Empty trash
  Future<int> emptyTrash(Uri baseUri, String token) =>
      _guard(() async {
    final url = _resolve(baseUri, 'api/trash/empty');
    final response = await _client.post(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _handleError(response);
    final data = jsonDecode(response.body);
    return (data['deletedCount'] as num?)?.toInt() ?? 0;
  });
}
