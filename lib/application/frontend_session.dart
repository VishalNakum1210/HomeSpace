import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';

abstract interface class SessionStore {
  Future<Map<String, dynamic>?> loadSession();
  Future<void> saveSession(Map<String, dynamic> data);
  Future<void> clearSession();
}

class MemorySessionStore implements SessionStore {
  Map<String, dynamic>? data;
  MemorySessionStore([this.data]);

  @override
  Future<Map<String, dynamic>?> loadSession() async => data;

  @override
  Future<void> saveSession(Map<String, dynamic> data) async {
    this.data = Map<String, dynamic>.from(data);
  }

  @override
  Future<void> clearSession() async {
    data = null;
  }
}

class FileSessionStore implements SessionStore {
  final Future<Directory> Function() directoryProvider;
  Future<Directory>? _directory;

  FileSessionStore(this.directoryProvider);

  factory FileSessionStore.android() => FileSessionStore(() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/homespace');
  });

  Future<File> _file() async {
    final dir = await (_directory ??= directoryProvider());
    await dir.create(recursive: true);
    return File('${dir.path}/session.json');
  }

  @override
  Future<Map<String, dynamic>?> loadSession() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveSession(Map<String, dynamic> data) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {}
  }

  @override
  Future<void> clearSession() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

class FrontendSession extends ChangeNotifier {
  final SessionStore? _store;
  bool _open = false;
  Uri? _serverUri;
  String? _authToken;
  String? _userId;
  String? _userEmail;
  String? _userName;
  AvatarTone? _avatarTone;
  bool _initialized = false;

  FrontendSession({
    Uri? serverUri,
    SessionStore? store,
    // ignore: prefer_initializing_formals
  })  : _serverUri = serverUri,
        // ignore: prefer_initializing_formals
        _store = store;

  bool get isOpen => _open;
  bool get isAuthenticated => _authToken != null && _authToken!.isNotEmpty;
  bool get isInitialized => _initialized;
  Uri? get serverUri => _serverUri;
  String? get authToken => _authToken;
  String? get userId => _userId;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  AvatarTone? get avatarTone => _avatarTone;

  Future<bool> restoreSession() async {
    if (_store == null) {
      _initialized = true;
      return false;
    }
    final data = await _store.loadSession();
    if (data != null &&
        data['token'] is String &&
        (data['token'] as String).isNotEmpty) {
      final token = data['token'] as String;
      final userId = data['userId'] as String?;
      final email = data['email'] as String?;
      final name = data['name'] as String?;
      final toneStr = data['avatarTone'] as String?;
      final uriStr = data['serverUri'] as String?;

      if (uriStr != null && uriStr.isNotEmpty) {
        _serverUri = Uri.tryParse(uriStr) ?? _serverUri;
      }
      _authToken = token;
      _userId = userId;
      _userEmail = email;
      _userName = name;
      if (toneStr != null) {
        _avatarTone = AvatarTone.values.asNameMap()[toneStr];
      }
      _open = true;
      _initialized = true;
      notifyListeners();
      return true;
    }
    _initialized = true;
    return false;
  }

  void enterPreview() {
    _open = true;
    notifyListeners();
  }

  Future<void> setAuthenticated({
    required Uri serverUri,
    required String token,
    required String userId,
    required String email,
    String? name,
    AvatarTone? avatarTone,
  }) async {
    _serverUri = serverUri;
    _authToken = token;
    _userId = userId;
    _userEmail = email;
    _userName = name;
    _avatarTone = avatarTone;
    _open = true;
    notifyListeners();

    if (_store != null) {
      await _store.saveSession({
        'serverUri': serverUri.toString(),
        'token': token,
        'userId': userId,
        'email': email,
        // ignore: use_null_aware_elements
        if (name != null) 'name': name,
        // ignore: use_null_aware_elements
        if (avatarTone != null) 'avatarTone': avatarTone.name,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> updateServerUri(Uri uri) async {
    _serverUri = uri;
    notifyListeners();
    if (_store != null && _authToken != null) {
      await _store.saveSession({
        'serverUri': uri.toString(),
        'token': _authToken,
        'userId': _userId,
        'email': _userEmail,
        // ignore: use_null_aware_elements
        if (_userName != null) 'name': _userName,
        // ignore: use_null_aware_elements
        if (_avatarTone != null) 'avatarTone': _avatarTone?.name,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> logout() async {
    _open = false;
    _authToken = null;
    _userId = null;
    _userEmail = null;
    _userName = null;
    _avatarTone = null;
    notifyListeners();

    if (_store != null) {
      await _store.clearSession();
    }
  }
}

class FrontendSessionScope extends InheritedNotifier<FrontendSession> {
  const FrontendSessionScope({
    super.key,
    required FrontendSession? session,
    required super.child,
  }) : super(notifier: session);

  static FrontendSession? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FrontendSessionScope>()
      ?.notifier;
}
