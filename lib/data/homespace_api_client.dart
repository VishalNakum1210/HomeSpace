import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../application/device_media_service.dart';
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
    int lastNotifiedMs = 0;
    int lastNotifiedBytes = 0;

    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        sent += chunk.length;
        sink.add(chunk);
        if (onProgress != null && total > 0) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final isComplete = sent >= total;
          // Throttle progress notifications to at most once per 200ms or on completion / 2% delta
          // This stops flooding Flutter's UI isolate with 4,800 rebuilds, unlocking full socket speed!
          if (isComplete || nowMs - lastNotifiedMs >= 200 || (sent - lastNotifiedBytes) >= (total * 0.02)) {
            lastNotifiedMs = nowMs;
            lastNotifiedBytes = sent;
            // Cap at 98% while streaming bytes so user sees real wire progress without premature 100%
            final reportedSent = isComplete
                ? (total * 0.98).round()
                : math.min(sent, (total * 0.98).round());
            onProgress!(reportedSent, total);
          }
        }
      },
      handleDone: (sink) {
        sink.close();
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
  final Uri? resolvedServerUri;

  const HomeSpaceAuthResult({
    required this.token,
    required this.userId,
    required this.email,
    required this.name,
    required this.avatarTone,
    required this.storageQuotaBytes,
    required this.storageUsedBytes,
    this.resolvedServerUri,
  });

  HomeSpaceAuthResult copyWith({
    String? token,
    String? userId,
    String? email,
    String? name,
    AvatarTone? avatarTone,
    int? storageQuotaBytes,
    int? storageUsedBytes,
    Uri? resolvedServerUri,
  }) => HomeSpaceAuthResult(
    token: token ?? this.token,
    userId: userId ?? this.userId,
    email: email ?? this.email,
    name: name ?? this.name,
    avatarTone: avatarTone ?? this.avatarTone,
    storageQuotaBytes: storageQuotaBytes ?? this.storageQuotaBytes,
    storageUsedBytes: storageUsedBytes ?? this.storageUsedBytes,
    resolvedServerUri: resolvedServerUri ?? this.resolvedServerUri,
  );
}

http.Client createHomeSpaceHttpClient() {
  final ioClient = HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) {
      // Allow connections to home servers over Tailscale Funnel, local LAN IPs, or self-signed certs
      return true;
    }
    ..connectionTimeout = const Duration(seconds: 30)
    ..idleTimeout = const Duration(seconds: 60);
  return IOClient(ioClient);
}

/// Resolves a remote network URI for a media item's thumbnail, preview, or original file.
/// If [asset] is already an HTTP(S) URL, its endpoint (/thumb, /preview, /file) is updated as requested.
/// If [asset] is a local path or filename but [serverUri] and [id] are provided, constructs the server URI.
Uri? resolveMediaUri({
  required String asset,
  required String id,
  Uri? serverUri,
  String endpoint = 'thumb',
}) {
  if (asset.startsWith('http://') || asset.startsWith('https://')) {
    final uri = Uri.parse(asset);
    final segments = uri.pathSegments;
    if (segments.length >= 2 &&
        (segments.last == 'thumb' ||
            segments.last == 'preview' ||
            segments.last == 'file')) {
      final newSegments = List<String>.from(segments);
      newSegments[newSegments.length - 1] = endpoint;
      if (serverUri != null) {
        return uri.replace(
          scheme: serverUri.scheme,
          host: serverUri.host,
          port: serverUri.hasPort ? serverUri.port : null,
          pathSegments: newSegments,
        );
      }
      return uri.replace(pathSegments: newSegments);
    }
    if (serverUri != null) {
      return uri.replace(
        scheme: serverUri.scheme,
        host: serverUri.host,
        port: serverUri.hasPort ? serverUri.port : null,
      );
    }
    return uri;
  }
  if (serverUri != null && id.isNotEmpty) {
    final cleanBase = serverUri.path.endsWith('/')
        ? serverUri.path.substring(0, serverUri.path.length - 1)
        : serverUri.path;
    final path = '$cleanBase/api/media/$id/$endpoint'.replaceAll('//', '/');
    return serverUri.replace(path: path);
  }
  return null;
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

  Future<HomeSpaceAuthResult> _postAuth({
    required Uri baseUri,
    required String path,
    required Map<String, dynamic> body,
    required int expectedStatus,
  }) async {
    final url = _resolve(baseUri, path);
    final response = await _client.post(
      url,
      headers: _headers(),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != expectedStatus) _handleError(response);

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
      resolvedServerUri: baseUri,
    );
  }

  // 2. Register
  Future<HomeSpaceAuthResult> register({
    required Uri baseUri,
    required String email,
    required String password,
    required String name,
    AvatarTone avatarTone = AvatarTone.orange,
  }) => _guard(() async {
    try {
      return await _postAuth(
        baseUri: baseUri,
        path: 'api/auth/register',
        body: {
          'email': email.trim(),
          'password': password,
          'name': name.trim(),
          'avatarTone': avatarTone.name,
        },
        expectedStatus: 201,
      );
    } on HandshakeException catch (_) {
      // If HTTPS handshake failed (e.g. self-signed or Tailscale Funnel issue),
      // check if common local HTTP ports or proxy respond
      if (baseUri.scheme == 'https') {
        final candidateUris = <Uri>[
          baseUri.replace(scheme: 'http'),
          if (baseUri.hasPort && baseUri.port == 8443)
            baseUri.replace(scheme: 'http', port: 8888),
          Uri.parse('http://127.0.0.1:8888'),
        ];
        for (final candidate in candidateUris) {
          try {
            final isHealthy = await checkHealth(candidate);
            if (isHealthy) {
              return await _postAuth(
                baseUri: candidate,
                path: 'api/auth/register',
                body: {
                  'email': email.trim(),
                  'password': password,
                  'name': name.trim(),
                  'avatarTone': avatarTone.name,
                },
                expectedStatus: 201,
              );
            }
          } catch (_) {}
        }
      }
      rethrow;
    }
  });

  // 3. Login
  Future<HomeSpaceAuthResult> login({
    required Uri baseUri,
    required String email,
    required String password,
  }) => _guard(() async {
    try {
      return await _postAuth(
        baseUri: baseUri,
        path: 'api/auth/login',
        body: {
          'email': email.trim(),
          'password': password,
        },
        expectedStatus: 200,
      );
    } on HandshakeException catch (_) {
      if (baseUri.scheme == 'https') {
        final candidateUris = <Uri>[
          baseUri.replace(scheme: 'http'),
          if (baseUri.hasPort && baseUri.port == 8443)
            baseUri.replace(scheme: 'http', port: 8888),
          Uri.parse('http://127.0.0.1:8888'),
        ];
        for (final candidate in candidateUris) {
          try {
            final isHealthy = await checkHealth(candidate);
            if (isHealthy) {
              return await _postAuth(
                baseUri: candidate,
                path: 'api/auth/login',
                body: {
                  'email': email.trim(),
                  'password': password,
                },
                expectedStatus: 200,
              );
            }
          } catch (_) {}
        }
      }
      rethrow;
    }
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

      final dateFromFileName = parseDateFromFileName(fileName);
      final rawTakenAt = DateTime.tryParse(takenAtIso);
      final effectiveTakenAt = dateFromFileName ?? rawTakenAt ?? DateTime.now();

      return MediaItem(
        id: id,
        asset: thumbUrl,
        title: fileName.isNotEmpty ? fileName : (isVideo ? 'Video' : 'Photo'),
        category: 'Library',
        takenAt: effectiveTakenAt,
        kind: isVideo ? MediaKind.video : MediaKind.photo,
      );
    }).toList();
  });

  // 5. Upload media (Supports photos & videos with live progress tracking)
  Future<MediaItem> uploadMedia({
    required Uri baseUri,
    required String token,
    List<int>? fileBytes,
    String? filePath,
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

    int totalByteSize = 0;
    if (filePath != null && filePath.isNotEmpty && File(filePath).existsSync()) {
      final f = File(filePath);
      totalByteSize = f.lengthSync();

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: filename,
          contentType: mediaType,
        ),
      );
    } else if (fileBytes != null) {
      totalByteSize = fileBytes.length;
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filename,
          contentType: mediaType,
        ),
      );
    } else {
      throw ArgumentError('Either fileBytes or a valid filePath must be provided to uploadMedia');
    }

    // Allow 30+ minutes for large videos or slower mobile network connections
    final sizeMb = totalByteSize / (1024 * 1024);
    final timeoutMinutes = math.max(30, (sizeMb / 10).ceil());
    final streamedResponse = await _client
        .send(request)
        .timeout(Duration(minutes: timeoutMinutes));
    final response = await http.Response.fromStream(streamedResponse)
        .timeout(const Duration(minutes: 5));

    if (response.statusCode != 200 && response.statusCode != 201) {
      _handleError(response);
    }

    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final id = map['id'] as String;
    final thumbUrl = _resolve(baseUri, 'api/media/$id/thumb').toString();
    final takenAtIso = map['takenAt'] as String? ?? map['createdAt'] as String;
    final mime = map['mimeType'] as String? ?? resolvedMime;
    final isVideo = mime.startsWith('video/');

    // For video uploads, asynchronously upload the high quality hardware frame thumbnail
    if (isVideo && filePath != null && filePath.isNotEmpty) {
      unawaited(() async {
        try {
          final thumbPath = await DeviceMediaService.getVideoThumbnail(filePath, fileName: filename);
          if (thumbPath != null && File(thumbPath).existsSync()) {
            final thumbBytes = await File(thumbPath).readAsBytes();
            if (thumbBytes.isNotEmpty) {
              await uploadThumbnail(
                baseUri: baseUri,
                token: token,
                mediaId: id,
                thumbBytes: thumbBytes,
              );
            }
          }
        } catch (_) {}
      }());
    }

    final dateFromFileName = parseDateFromFileName(filename);
    final rawTakenAt = DateTime.tryParse(takenAtIso);
    final effectiveTakenAt = takenAt ?? dateFromFileName ?? rawTakenAt ?? DateTime.now();

    return MediaItem(
      id: id,
      asset: thumbUrl,
      title: map['fileName'] as String? ?? filename,
      category: 'Uploads',
      takenAt: effectiveTakenAt,
      kind: isVideo ? MediaKind.video : MediaKind.photo,
    );
  });

  // 5b. Upload / update thumbnail for a media item
  Future<bool> uploadThumbnail({
    required Uri baseUri,
    required String token,
    required String mediaId,
    required List<int> thumbBytes,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/media/$mediaId/thumb');
    final request = http.MultipartRequest('PUT', url)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(
        http.MultipartFile.fromBytes(
          'thumb',
          thumbBytes,
          filename: 'thumb.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    return response.statusCode >= 200 && response.statusCode < 300;
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
