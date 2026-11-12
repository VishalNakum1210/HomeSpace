import 'dart:convert';
import 'package:http/http.dart' as http;

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

class HomeSpaceApiClient {
  final http.Client _client;

  HomeSpaceApiClient({http.Client? client}) : _client = client ?? http.Client();

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

  // 1. Health check
  Future<bool> checkHealth(Uri baseUri) async {
    final url = _resolve(baseUri, 'api/health');
    try {
      final response = await _client.get(url, headers: {'Accept': 'application/json'}).timeout(
        const Duration(seconds: 5),
      );
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
  }) async {
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
    );

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
  }

  // 3. Login
  Future<HomeSpaceAuthResult> login({
    required Uri baseUri,
    required String email,
    required String password,
  }) async {
    final url = _resolve(baseUri, 'api/auth/login');
    final response = await _client.post(
      url,
      headers: _headers(),
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
      }),
    );

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
  }

  // 4. Fetch media items
  Future<List<MediaItem>> fetchMedia(Uri baseUri, String token, {bool trashed = false}) async {
    final url = _resolve(baseUri, 'api/media', {'trashed': trashed ? '1' : '0'});
    final response = await _client.get(url, headers: _headers(token));

    if (response.statusCode != 200) _handleError(response);

    final data = jsonDecode(response.body);
    final items = (data['items'] as List<dynamic>?) ?? [];

    return items.map((raw) {
      final map = raw as Map<String, dynamic>;
      final id = map['id'] as String;
      final thumbUrl = _resolve(baseUri, 'api/media/$id/thumb').toString();
      final takenAtIso = map['takenAt'] as String? ?? map['createdAt'] as String;

      return MediaItem(
        id: id,
        asset: thumbUrl,
        title: map['fileName'] as String? ?? 'Photo',
        category: 'Library',
        takenAt: DateTime.tryParse(takenAtIso) ?? DateTime.now(),
      );
    }).toList();
  }

  // 5. Upload media
  Future<MediaItem> uploadMedia({
    required Uri baseUri,
    required String token,
    required List<int> fileBytes,
    required String filename,
    String mimeType = 'image/jpeg',
  }) async {
    final url = _resolve(baseUri, 'api/media/upload');
    final request = http.MultipartRequest('POST', url)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filename,
        ),
      );

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 201) _handleError(response);

    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final id = map['id'] as String;
    final thumbUrl = _resolve(baseUri, 'api/media/$id/thumb').toString();
    final takenAtIso = map['takenAt'] as String? ?? map['createdAt'] as String;

    return MediaItem(
      id: id,
      asset: thumbUrl,
      title: map['fileName'] as String? ?? filename,
      category: 'Uploads',
      takenAt: DateTime.tryParse(takenAtIso) ?? DateTime.now(),
    );
  }

  // 6. Favorite toggle
  Future<void> toggleFavorite(Uri baseUri, String token, String mediaId, bool favorite) async {
    final url = _resolve(baseUri, 'api/media/$mediaId');
    final response = await _client.patch(
      url,
      headers: _headers(token),
      body: jsonEncode({'favorite': favorite}),
    );
    if (response.statusCode != 200) _handleError(response);
  }

  // 7. Trash media
  Future<void> trashMedia(Uri baseUri, String token, String mediaId) async {
    final url = _resolve(baseUri, 'api/media/$mediaId/trash');
    final response = await _client.post(url, headers: _headers(token));
    if (response.statusCode != 200) _handleError(response);
  }

  // 8. Restore media
  Future<void> restoreMedia(Uri baseUri, String token, String mediaId) async {
    final url = _resolve(baseUri, 'api/media/$mediaId/restore');
    final response = await _client.post(url, headers: _headers(token));
    if (response.statusCode != 200) _handleError(response);
  }

  // 9. Permanent delete
  Future<void> deleteMedia(Uri baseUri, String token, String mediaId) async {
    final url = _resolve(baseUri, 'api/media/$mediaId');
    final response = await _client.delete(url, headers: _headers(token));
    if (response.statusCode != 200) _handleError(response);
  }

  // 10. Fetch albums
  Future<List<Album>> fetchAlbums(Uri baseUri, String token) async {
    final url = _resolve(baseUri, 'api/albums');
    final response = await _client.get(url, headers: _headers(token));

    if (response.statusCode != 200) _handleError(response);

    final data = jsonDecode(response.body);
    final albums = (data['albums'] as List<dynamic>?) ?? [];

    return albums.map<Album>((raw) {
      final map = raw as Map<String, dynamic>;
      return Album(
        id: map['id'] as String,
        title: map['title'] as String,
        description: map['description'] as String? ?? '',
        coverId: map['coverMediaId'] as String?,
        mediaIds: const [],
        memberships: [
          AlbumMembership(
            map['ownerId'] as String,
            AlbumRole.values.byName(map['userRole'] as String? ?? 'owner'),
          ),
        ],
        addedBy: const {},
      );
    }).toList();
  }

  // 11. Create album
  Future<String> createAlbum({
    required Uri baseUri,
    required String token,
    required String title,
    String description = '',
    List<String> mediaIds = const [],
    String? coverId,
  }) async {
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
    );

    if (response.statusCode != 201) _handleError(response);
    final data = jsonDecode(response.body);
    return data['id'] as String;
  }

  // 12. Delete album
  Future<void> deleteAlbum(Uri baseUri, String token, String albumId) async {
    final url = _resolve(baseUri, 'api/albums/$albumId');
    final response = await _client.delete(url, headers: _headers(token));
    if (response.statusCode != 200) _handleError(response);
  }

  // 13. Empty trash
  Future<int> emptyTrash(Uri baseUri, String token) async {
    final url = _resolve(baseUri, 'api/trash/empty');
    final response = await _client.post(url, headers: _headers(token));
    if (response.statusCode != 200) _handleError(response);
    final data = jsonDecode(response.body);
    return (data['deletedCount'] as num?)?.toInt() ?? 0;
  }
}
