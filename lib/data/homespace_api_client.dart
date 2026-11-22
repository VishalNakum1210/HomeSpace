import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';

import '../domain/models.dart';

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

/// Resolves a remote network URI for an asset if it is already an HTTP(S) URL.
/// For local device media, returns null so the app uses local file decoders directly.
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
    var sent = 0;

    final controller = StreamController<List<int>>(sync: true);
    byteStream.listen(
      (chunk) {
        sent += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress!(sent, total);
        }
        controller.add(chunk);
      },
      onDone: () => controller.close(),
      onError: (e, st) => controller.addError(e, st),
      cancelOnError: true,
    );

    return http.ByteStream(controller.stream);
  }
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

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SocketException catch (e) {
      throw HomeSpaceServerException(
        code: 'SERVER_UNREACHABLE',
        message: 'Cannot reach home server. Check that your laptop is on and the address is correct: ${e.message}',
        statusCode: 0,
      );
    } on HandshakeException catch (e) {
      throw HomeSpaceServerException(
        code: 'TLS_HANDSHAKE_FAILED',
        message: 'Secure SSL/TLS handshake failed with your home server. (${e.message})',
        statusCode: 0,
      );
    } on TlsException catch (e) {
      throw HomeSpaceServerException(
        code: 'TLS_HANDSHAKE_FAILED',
        message: 'Secure SSL/TLS handshake failed with your home server. (${e.message})',
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
      // If HTTPS handshake failed, check if common local HTTP ports respond
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

  // 4. Fetch media timeline
  Future<List<MediaItem>> fetchMedia({
    required Uri baseUri,
    required String token,
    int limit = 150,
    int offset = 0,
    bool favoriteOnly = false,
    bool trashedOnly = false,
  }) => _guard(() async {
    final query = <String, dynamic>{
      'limit': limit,
      'offset': offset,
      if (favoriteOnly) 'favorite': 'true',
      if (trashedOnly) 'trashed': 'true',
    };
    final url = _resolve(baseUri, 'api/media', query);
    final response = await _client.get(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) _handleError(response);

    final data = jsonDecode(response.body);
    final items = (data['items'] as List<dynamic>? ?? []);
    return items.map((raw) {
      final m = raw as Map<String, dynamic>;
      final isVideo = m['kind'] == 'video';
      final id = m['id'] as String;
      final fileUri = resolveMediaUri(
        asset: '',
        id: id,
        serverUri: baseUri,
        endpoint: 'file',
      );

      return MediaItem(
        id: id,
        asset: fileUri?.toString() ?? '',
        title: m['filename'] as String? ?? 'Memory',
        category: 'Camera',
        takenAt: DateTime.tryParse(m['takenAt'] as String? ?? '') ?? DateTime.now(),
        kind: isVideo ? MediaKind.video : MediaKind.photo,
        isSynced: true,
      );
    }).toList();
  });

  // 5. Upload media file
  Future<MediaItem> uploadMediaFile({
    required Uri baseUri,
    required String token,
    required String filePath,
    required String filename,
    String? mimeType,
    DateTime? takenAt,
    void Function(int bytesSent, int totalBytes)? onProgress,
  }) => _guard(() async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw HomeSpaceServerException(
        code: 'FILE_NOT_FOUND',
        message: 'File not found on device: $filePath',
        statusCode: 400,
      );
    }

    final takenIso = (takenAt ?? DateTime.now()).toUtc().toIso8601String();
    final url = _resolve(baseUri, 'api/media/upload', {'takenAt': takenIso});

    final request = _MultipartRequestWithProgress(
      'POST',
      url,
      onProgress: onProgress,
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['x-taken-at'] = takenIso;

    final resolvedMime = mimeType ??
        (filename.toLowerCase().endsWith('.mp4') || filename.toLowerCase().endsWith('.mov')
            ? 'video/mp4'
            : 'image/jpeg');

    final multipartFile = await http.MultipartFile.fromPath(
      'file',
      filePath,
      filename: filename,
      contentType: MediaType.parse(resolvedMime),
    );
    request.files.add(multipartFile);

    final streamed = await _client.send(request).timeout(const Duration(minutes: 10));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 201 && response.statusCode != 200) {
      _handleError(response);
    }

    final data = jsonDecode(response.body);
    final media = data['media'] as Map<String, dynamic>;
    final id = media['id'] as String;
    final isVideo = media['kind'] == 'video';

    return MediaItem(
      id: id,
      asset: filePath,
      title: media['filename'] as String? ?? filename,
      category: 'Camera',
      takenAt: DateTime.tryParse(media['takenAt'] as String? ?? '') ?? (takenAt ?? DateTime.now()),
      kind: isVideo ? MediaKind.video : MediaKind.photo,
      isSynced: true,
    );
  });

  // 5b. Upload media thumbnail
  Future<void> uploadMediaThumbnail({
    required Uri baseUri,
    required String token,
    required String mediaId,
    required String thumbPath,
  }) => _guard(() async {
    final file = File(thumbPath);
    if (!await file.exists()) return;

    final url = _resolve(baseUri, 'api/media/$mediaId/thumb');
    final request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        thumbPath,
        filename: 'thumb_$mediaId.webp',
        contentType: MediaType('image', 'webp'),
      ),
    );
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    await http.Response.fromStream(streamed);
  });

  // 6. Toggle favorite
  Future<void> toggleFavorite({
    required Uri baseUri,
    required String token,
    required String mediaId,
    required bool isFavorite,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/media/$mediaId');
    final response = await _client.patch(
      url,
      headers: _headers(token),
      body: jsonEncode({'isFavorite': isFavorite}),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);
  });

  // 7. Move to trash (bulk)
  Future<void> trashMedia({
    required Uri baseUri,
    required String token,
    required List<String> mediaIds,
    List<String>? filenames,
  }) => _guard(() async {
    if (mediaIds.isEmpty && (filenames == null || filenames.isEmpty)) return;
    final url = _resolve(baseUri, 'api/media/trash');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({
        'ids': mediaIds,
        if (filenames != null && filenames.isNotEmpty) 'filenames': filenames,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);
  });

  // 8. Restore from trash (bulk)
  Future<void> restoreMedia({
    required Uri baseUri,
    required String token,
    required List<String> mediaIds,
    List<String>? filenames,
  }) => _guard(() async {
    if (mediaIds.isEmpty && (filenames == null || filenames.isEmpty)) return;
    final url = _resolve(baseUri, 'api/media/restore');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({
        'ids': mediaIds,
        if (filenames != null && filenames.isNotEmpty) 'filenames': filenames,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);
  });

  // 9. Delete permanently (bulk)
  Future<void> deleteMediaPermanently({
    required Uri baseUri,
    required String token,
    required List<String> mediaIds,
    List<String>? filenames,
  }) => _guard(() async {
    if (mediaIds.isEmpty && (filenames == null || filenames.isEmpty)) return;
    final url = _resolve(baseUri, 'api/media/delete');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({
        'ids': mediaIds,
        if (filenames != null && filenames.isNotEmpty) 'filenames': filenames,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);
  });

  // 9b. Empty trash (permanently delete all trashed items)
  Future<void> emptyTrash({
    required Uri baseUri,
    required String token,
    List<String>? mediaIds,
    List<String>? filenames,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/trash/empty');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({
        if (mediaIds != null && mediaIds.isNotEmpty) 'ids': mediaIds,
        if (filenames != null && filenames.isNotEmpty) 'filenames': filenames,
      }),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) _handleError(response);
  });

  // 9c. Fetch trashed media
  Future<List<MediaItem>> fetchTrash({
    required Uri baseUri,
    required String token,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/trash');
    final response = await _client.get(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) _handleError(response);

    final data = jsonDecode(response.body);
    final items = (data['items'] as List<dynamic>? ?? []);
    return items
        .where((raw) {
          final m = raw as Map<String, dynamic>;
          return m['isTrashed'] == true || m['is_trashed'] == true || m['is_trashed'] == 1;
        })
        .map((raw) {
          final m = raw as Map<String, dynamic>;
          final id = m['id'] as String;
          final fileUri = resolveMediaUri(
            asset: '',
            id: id,
            serverUri: baseUri,
            endpoint: 'file',
          );
          return MediaItem(
            id: id,
            asset: fileUri?.toString() ?? '',
            title: m['filename'] as String? ?? 'Memory',
            category: 'Camera',
            takenAt: DateTime.tryParse(m['takenAt'] as String? ?? '') ?? DateTime.now(),
            kind: m['kind'] == 'video' ? MediaKind.video : MediaKind.photo,
            isSynced: true,
          );
        })
        .toList();
  });

  // 10. Fetch albums
  Future<List<Album>> fetchAlbums({
    required Uri baseUri,
    required String token,
    String? currentUserId,
    bool sharedOnly = false,
  }) => _guard(() async {
    final query = <String, dynamic>{
      if (sharedOnly) 'shared': 'true',
    };
    final url = _resolve(baseUri, 'api/albums', query);
    final response = await _client.get(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) _handleError(response);

    final data = jsonDecode(response.body);
    final albums = (data['albums'] as List<dynamic>? ?? []);
    final fallbackUser = currentUserId ?? 'member-maya';

    return albums.map((raw) {
      final a = raw as Map<String, dynamic>;
      final id = a['id'] as String;
      final rawOwner = a['userId'] as String?;
      final isOwner = rawOwner == null || rawOwner == fallbackUser || rawOwner == 'user-me';
      final ownerId = isOwner ? fallbackUser : rawOwner;
      final mediaIds = (a['mediaIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      final memberships = [
        AlbumMembership(ownerId, AlbumRole.owner),
        if (!isOwner)
          AlbumMembership(fallbackUser, AlbumRole.contributor),
      ];

      return Album(
        id: id,
        title: a['title'] as String? ?? 'Album',
        description: a['description'] as String? ?? '',
        mediaIds: mediaIds,
        coverId: a['coverMediaId'] as String?,
        memberships: memberships,
        addedBy: {for (final m in mediaIds) m: fallbackUser},
      );
    }).toList();
  });

  // 11. Create remote album
  Future<Album> createRemoteAlbum({
    required Uri baseUri,
    required String token,
    required String title,
    String description = '',
    List<String> mediaIds = const [],
    String? coverMediaId,
    bool isShared = false,
    String? id,
    String? currentUserId,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/albums');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({
        'id': ?id,
        'title': title,
        'description': description,
        'mediaIds': mediaIds,
        'coverMediaId': ?coverMediaId,
        'isShared': isShared,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 201 && response.statusCode != 200) {
      _handleError(response);
    }

    final data = jsonDecode(response.body);
    final a = data['album'] as Map<String, dynamic>;
    final albumId = a['id'] as String;
    final ownerId = a['userId'] as String? ?? (currentUserId ?? 'user-me');
    final returnedMediaIds = (a['mediaIds'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    return Album(
      id: albumId,
      title: a['title'] as String? ?? title,
      description: a['description'] as String? ?? description,
      mediaIds: returnedMediaIds,
      coverId: a['coverMediaId'] as String? ?? coverMediaId,
      memberships: [AlbumMembership(ownerId, AlbumRole.owner)],
      addedBy: {for (final m in returnedMediaIds) m: ownerId},
    );
  });

  // 12. Update remote album
  Future<void> updateRemoteAlbum({
    required Uri baseUri,
    required String token,
    required String albumId,
    String? title,
    String? description,
    String? coverMediaId,
    bool? isShared,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/albums/$albumId');
    final body = <String, dynamic>{
      'title': ?title,
      'description': ?description,
      'coverMediaId': ?coverMediaId,
      'isShared': ?isShared,
    };
    if (body.isEmpty) return;

    final response = await _client.patch(
      url,
      headers: _headers(token),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);
  });

  // 13. Add media to remote album
  Future<void> addMediaToRemoteAlbum({
    required Uri baseUri,
    required String token,
    required String albumId,
    required List<String> mediaIds,
  }) => _guard(() async {
    if (mediaIds.isEmpty) return;
    final url = _resolve(baseUri, 'api/albums/$albumId/media');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({'mediaIds': mediaIds}),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);
  });

  // 14. Remove media from remote album
  Future<void> removeMediaFromRemoteAlbum({
    required Uri baseUri,
    required String token,
    required String albumId,
    required List<String> mediaIds,
  }) => _guard(() async {
    if (mediaIds.isEmpty) return;
    final url = _resolve(baseUri, 'api/albums/$albumId/media/remove');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({'mediaIds': mediaIds}),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);
  });

  // 15. Delete remote album
  Future<void> deleteRemoteAlbum({
    required Uri baseUri,
    required String token,
    required String albumId,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/albums/$albumId');
    final response = await _client.delete(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);
  });

  // 16. Fetch storage breakdown
  Future<StorageBreakdown> fetchStorageBreakdown({
    required Uri baseUri,
    required String token,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/media/storage-breakdown');
    final response = await _client.get(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return StorageBreakdown(
      photosBytes: (data['photosBytes'] as num?)?.toInt() ?? 0,
      videosBytes: (data['videosBytes'] as num?)?.toInt() ?? 0,
      totalUsedBytes: (data['totalUsedBytes'] as num?)?.toInt() ?? 0,
      quotaBytes: (data['quotaBytes'] as num?)?.toInt() ?? 15 * 1024 * 1024 * 1024,
    );
  });

  // 17. Fetch family admin users
  Future<List<FamilyAccount>> fetchAdminUsers({
    required Uri baseUri,
    required String token,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/admin/users');
    final response = await _client.get(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final users = (data['users'] as List<dynamic>? ?? []);
    return users.map((u) {
      final map = u as Map<String, dynamic>;
      final rawTone = map['avatarTone'] as String? ?? 'orange';
      final tone = AvatarTone.values.firstWhere(
        (t) => t.name == rawTone,
        orElse: () => AvatarTone.orange,
      );
      return FamilyAccount(
        id: map['id'] as String,
        email: map['email'] as String? ?? '',
        name: map['name'] as String? ?? '',
        avatarTone: tone,
        isAdmin: map['isAdmin'] == true,
        storageQuotaBytes: (map['storageQuotaBytes'] as num?)?.toInt() ?? 15 * 1024 * 1024 * 1024,
        storageUsedBytes: (map['storageUsedBytes'] as num?)?.toInt() ?? 0,
        createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt'] as String) : null,
      );
    }).toList();
  });

  // 18. Create family user (admin)
  Future<FamilyAccount> createAdminUser({
    required Uri baseUri,
    required String token,
    required String name,
    required String email,
    required String password,
    String avatarTone = 'orange',
    int storageQuotaBytes = 15 * 1024 * 1024 * 1024,
    bool isAdmin = false,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/admin/users');
    final response = await _client.post(
      url,
      headers: _headers(token),
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'avatarTone': avatarTone,
        'storageQuotaBytes': storageQuotaBytes,
        'isAdmin': isAdmin,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 201) _handleError(response);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final map = data['user'] as Map<String, dynamic>;
    final rawTone = map['avatarTone'] as String? ?? 'orange';
    final tone = AvatarTone.values.firstWhere(
      (t) => t.name == rawTone,
      orElse: () => AvatarTone.orange,
    );
    return FamilyAccount(
      id: map['id'] as String,
      email: map['email'] as String? ?? '',
      name: map['name'] as String? ?? '',
      avatarTone: tone,
      isAdmin: map['isAdmin'] == true,
      storageQuotaBytes: (map['storageQuotaBytes'] as num?)?.toInt() ?? storageQuotaBytes,
      storageUsedBytes: (map['storageUsedBytes'] as num?)?.toInt() ?? 0,
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt'] as String) : null,
    );
  });

  // 19. Delete family user (admin)
  Future<void> deleteAdminUser({
    required Uri baseUri,
    required String token,
    required String userId,
  }) => _guard(() async {
    final url = _resolve(baseUri, 'api/admin/users/$userId');
    final response = await _client.delete(
      url,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) _handleError(response);
  });
}
