import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

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
}
