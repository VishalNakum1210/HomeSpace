import 'dart:async';
import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../domain/server_address.dart';
import 'homespace_api_client.dart';

class HttpConnectionRepository extends ChangeNotifier implements ConnectionRepository {
  final HomeSpaceApiClient _apiClient;
  ConnectionStatus _status;
  int _attempt = 0;
  bool _disposed = false;

  HttpConnectionRepository({
    HomeSpaceApiClient? apiClient,
    Uri? initialAddress,
  })  : _apiClient = apiClient ?? HomeSpaceApiClient(),
        _status = initialAddress != null
            ? ConnectionStatus(
                ConnectionPhase.disconnected,
                'Ready to connect to $initialAddress',
                address: initialAddress,
                isDemo: false,
              )
            : const ConnectionStatus(
                ConnectionPhase.disconnected,
                'No home server is connected.',
                isDemo: false,
              );

  @override
  ConnectionStatus get status => _status;

  @override
  Future<ConnectionStatus> connect(Uri address) async {
    if (_disposed) throw const LocalActionException('This session is closed.');
    parseServerAddress(address.toString());
    final attempt = ++_attempt;

    _status = ConnectionStatus(
      ConnectionPhase.connecting,
      'Connecting to home server…',
      address: address,
      isDemo: false,
    );
    notifyListeners();

    try {
      final isHealthy = await _apiClient.checkHealth(address);
      if (attempt != _attempt || _disposed) return _status;

      if (isHealthy) {
        _status = ConnectionStatus(
          ConnectionPhase.connected,
          'Connected to HomeSpace server.',
          address: address,
          isDemo: false,
        );
      } else {
        _status = ConnectionStatus(
          ConnectionPhase.failed,
          'Could not find a HomeSpace server at this address. Check IP and port.',
          address: address,
          isDemo: false,
        );
      }
    } catch (_) {
      if (attempt != _attempt || _disposed) return _status;
      _status = ConnectionStatus(
        ConnectionPhase.failed,
        'Connection failed. Ensure laptop is on and reachable.',
        address: address,
        isDemo: false,
      );
    }

    notifyListeners();
    return _status;
  }

  @override
  void disconnect() {
    if (_disposed) return;
    _attempt++;
    _status = const ConnectionStatus(
      ConnectionPhase.disconnected,
      'Disconnected from home server.',
      isDemo: false,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _attempt++;
    _apiClient.close();
    super.dispose();
  }
}

class _PendingUploadTask {
  final UploadItem item;
  final List<int> bytes;
  final String filename;
  final String? mimeType;
  final String? targetAlbumId;

  _PendingUploadTask({
    required this.item,
    required this.bytes,
    required this.filename,
    this.mimeType,
    this.targetAlbumId,
  });
}

class HttpUploadRepository extends ChangeNotifier implements UploadRepository {
  final List<UploadItem> _items = [];
  final List<_PendingUploadTask> _pendingQueue = [];
  bool _isProcessing = false;
  final HomeSpaceApiClient _apiClient;
  final Uri? Function() _getServerAddress;
  final String? Function() _getAuthToken;
  final void Function(MediaItem item, String? targetAlbumId)? onMediaUploaded;

  HttpUploadRepository({
    HomeSpaceApiClient? apiClient,
    required Uri? Function() getServerAddress,
    required String? Function() getAuthToken,
    this.onMediaUploaded,
  })  : _apiClient = apiClient ?? HomeSpaceApiClient(),
        // ignore: prefer_initializing_formals
        _getServerAddress = getServerAddress,
        // ignore: prefer_initializing_formals
        _getAuthToken = getAuthToken;

  @override
  List<UploadItem> get items => List.unmodifiable(_items);

  void queueUpload({
    required String id,
    required String mediaId,
    required int totalBytes,
    required List<int> bytes,
    required String filename,
    String? mimeType,
    String? targetAlbumId,
  }) {
    final item = UploadItem(
      id: id,
      mediaId: mediaId,
      title: filename,
      totalBytes: totalBytes,
      phase: UploadPhase.queued,
    );
    _items.add(item);
    _pendingQueue.add(_PendingUploadTask(
      item: item,
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
      targetAlbumId: targetAlbumId,
    ));
    notifyListeners();

    _processQueue();
  }

  void _processQueue() {
    if (_isProcessing || _pendingQueue.isEmpty) return;
    _isProcessing = true;
    _runQueueLoop();
  }

  Future<void> _runQueueLoop() async {
    while (_pendingQueue.isNotEmpty) {
      final task = _pendingQueue.removeAt(0);
      final currentIdx = _items.indexWhere((e) => e.id == task.item.id);
      if (currentIdx == -1 ||
          _items[currentIdx].phase == UploadPhase.canceled ||
          _items[currentIdx].phase == UploadPhase.paused) {
        continue;
      }
      await _startUpload(
        task.item,
        task.bytes,
        task.filename,
        task.mimeType,
        task.targetAlbumId,
      );
    }
    _isProcessing = false;
  }

  Future<void> _startUpload(
    UploadItem item,
    List<int> bytes,
    String filename,
    String? mimeType,
    String? targetAlbumId,
  ) async {
    final serverUri = _getServerAddress();
    final token = _getAuthToken();

    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) return;

    if (serverUri == null || token == null) {
      _items[idx] = item.copyWith(phase: UploadPhase.failed);
      notifyListeners();
      return;
    }

    _items[idx] = item.copyWith(phase: UploadPhase.uploading);
    notifyListeners();

    try {
      final uploadedMedia = await _apiClient.uploadMedia(
        baseUri: serverUri,
        token: token,
        fileBytes: bytes,
        filename: filename,
        mimeType: mimeType,
        onProgress: (sent, total) {
          final currentIdx = _items.indexWhere((e) => e.id == item.id);
          if (currentIdx != -1) {
            _items[currentIdx] = _items[currentIdx].copyWith(
              bytesSent: sent,
              totalBytes: total,
              phase: UploadPhase.uploading,
            );
            notifyListeners();
          }
        },
      );

      final currentIdx = _items.indexWhere((e) => e.id == item.id);
      if (currentIdx != -1) {
        _items[currentIdx] = item.copyWith(
          bytesSent: item.totalBytes,
          phase: UploadPhase.completed,
        );
        notifyListeners();
      }

      onMediaUploaded?.call(uploadedMedia, targetAlbumId);
    } catch (_) {
      final currentIdx = _items.indexWhere((e) => e.id == item.id);
      if (currentIdx != -1) {
        _items[currentIdx] = item.copyWith(phase: UploadPhase.failed);
        notifyListeners();
      }
    }
  }

  @override
  void pause(String id) {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx != -1 && _items[idx].phase == UploadPhase.uploading) {
      _items[idx] = _items[idx].copyWith(phase: UploadPhase.paused);
      notifyListeners();
    }
  }

  @override
  void resume(String id) {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx != -1 && _items[idx].phase == UploadPhase.paused) {
      _items[idx] = _items[idx].copyWith(phase: UploadPhase.queued);
      notifyListeners();
    }
  }

  @override
  void retry(String id) {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx != -1 && _items[idx].phase == UploadPhase.failed) {
      _items[idx] = _items[idx].copyWith(phase: UploadPhase.queued);
      notifyListeners();
    }
  }

  @override
  void cancel(String id) {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _items[idx] = _items[idx].copyWith(phase: UploadPhase.canceled);
      _pendingQueue.removeWhere((task) => task.item.id == id);
      notifyListeners();
    }
  }

  @override
  void clearCompleted() {
    _items.removeWhere((item) =>
        item.phase == UploadPhase.completed ||
        item.phase == UploadPhase.canceled);
    notifyListeners();
  }
}
