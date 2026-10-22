import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

class DemoConnectionRepository extends ChangeNotifier
    implements ConnectionRepository {
  DemoScenario scenario;
  final Duration delay;
  int _attempt = 0;
  ConnectionStatus _status = const ConnectionStatus(
    ConnectionPhase.disconnected,
    'Demo mode. No server is connected.',
  );
  DemoConnectionRepository({
    this.scenario = DemoScenario.populated,
    this.delay = Duration.zero,
  });
  @override
  ConnectionStatus get status => _status;

  @override
  Future<ConnectionStatus> connect(Uri address) async {
    if (!['http', 'https'].contains(address.scheme) ||
        address.host.isEmpty ||
        address.userInfo.isNotEmpty) {
      throw const LocalActionException(
        'Enter an HTTP or HTTPS server address without credentials.',
      );
    }
    final attempt = ++_attempt;
    _status = ConnectionStatus(
      ConnectionPhase.connecting,
      'Simulating a connection…',
      address: address,
    );
    notifyListeners();
    await Future<void>.delayed(delay);
    if (attempt != _attempt) return _status;
    _status = switch (scenario) {
      DemoScenario.offline => ConnectionStatus(
        ConnectionPhase.offline,
        'Offline demo. Showing saved local content.',
        address: address,
      ),
      DemoScenario.failed => ConnectionStatus(
        ConnectionPhase.failed,
        'Demo connection failed. Try again.',
        address: address,
      ),
      _ => ConnectionStatus(
        ConnectionPhase.connected,
        'Demo connection only. No files are sent.',
        address: address,
      ),
    };
    notifyListeners();
    return _status;
  }

  @override
  void disconnect() {
    _attempt++;
    _status = const ConnectionStatus(
      ConnectionPhase.disconnected,
      'Demo mode. No server is connected.',
    );
    notifyListeners();
  }
}

class DemoUploadRepository extends ChangeNotifier implements UploadRepository {
  List<UploadItem> _items = [];
  DemoUploadRepository({DemoScenario scenario = DemoScenario.populated}) {
    reset(scenario);
  }
  bool get isDemo => true;
  @override
  List<UploadItem> get items => List.unmodifiable(_items);
  int count(UploadPhase phase) =>
      _items.where((item) => item.phase == phase).length;

  void reset(DemoScenario scenario) {
    _items = scenario == DemoScenario.empty
        ? []
        : const [
            UploadItem(
              id: 'upload-1',
              mediaId: 'media-01',
              totalBytes: 1000,
              bytesSent: 1000,
              phase: UploadPhase.completed,
            ),
            UploadItem(
              id: 'upload-2',
              mediaId: 'media-02',
              totalBytes: 2000,
              bytesSent: 2000,
              phase: UploadPhase.completed,
            ),
            UploadItem(
              id: 'upload-3',
              mediaId: 'media-03',
              totalBytes: 3000,
              bytesSent: 600,
              phase: UploadPhase.uploading,
            ),
            UploadItem(id: 'upload-4', mediaId: 'media-04', totalBytes: 4000),
            UploadItem(
              id: 'upload-5',
              mediaId: 'media-05',
              totalBytes: 5000,
              bytesSent: 500,
              phase: UploadPhase.failed,
            ),
          ];
    if (scenario == DemoScenario.offline) {
      _items = [
        for (final item in _items)
          item.phase == UploadPhase.uploading
              ? item.copyWith(phase: UploadPhase.paused)
              : item,
      ];
    }
    notifyListeners();
  }

  void _change(String id, UploadItem Function(UploadItem) update) {
    if (!_items.any((item) => item.id == id)) {
      throw const LocalActionException('That demo upload is unavailable.');
    }
    _items = [for (final item in _items) item.id == id ? update(item) : item];
    notifyListeners();
  }

  @override
  void pause(String id) => _change(
    id,
    (item) => [UploadPhase.uploading, UploadPhase.queued].contains(item.phase)
        ? item.copyWith(phase: UploadPhase.paused)
        : item,
  );
  @override
  void resume(String id) => _change(
    id,
    (item) => item.phase == UploadPhase.paused
        ? item.copyWith(phase: UploadPhase.queued)
        : item,
  );
  @override
  void retry(String id) => _change(
    id,
    (item) => item.phase == UploadPhase.failed
        ? item.copyWith(bytesSent: 0, phase: UploadPhase.queued)
        : item,
  );
  @override
  void cancel(String id) => _change(
    id,
    (item) => item.phase == UploadPhase.completed
        ? item
        : item.copyWith(phase: UploadPhase.canceled),
  );

  // Explicit fixture controls. No clock or timer invents background uploads.
  void simulateProgress(String id, int bytesSent) => _change(id, (item) {
    if (bytesSent < item.bytesSent || bytesSent > item.totalBytes) {
      throw const LocalActionException('Invalid demo progress.');
    }
    if (![UploadPhase.queued, UploadPhase.uploading].contains(item.phase)) {
      throw const LocalActionException('Resume or retry this demo item first.');
    }
    return item.copyWith(
      bytesSent: bytesSent,
      phase: bytesSent == item.totalBytes
          ? UploadPhase.completed
          : UploadPhase.uploading,
    );
  });
}
