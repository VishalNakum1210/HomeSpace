import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

import '../data/homespace_api_client.dart';
import '../domain/models.dart';
import 'device_media_service.dart';

enum DownloadPhase {
  idle,
  connecting,
  downloading,
  saving,
  completed,
  failed,
}

class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._internal();
  factory DownloadService() => instance;
  DownloadService._internal();

  DownloadPhase _phase = DownloadPhase.idle;
  String? _currentMediaId;
  String? _currentFileName;
  double? _progress;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String _title = '';
  String _detail = '';
  String? _savedPath;
  String? _errorMessage;
  Timer? _dismissTimer;

  DownloadPhase get phase => _phase;
  bool get isDownloading =>
      _phase == DownloadPhase.connecting ||
      _phase == DownloadPhase.downloading ||
      _phase == DownloadPhase.saving;
  bool get hasActiveDownload => _phase != DownloadPhase.idle;
  String? get currentMediaId => _currentMediaId;
  String? get currentFileName => _currentFileName;
  double? get progress => _progress;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;
  String get title => _title;
  String get detail => _detail;
  String? get savedPath => _savedPath;
  String? get errorMessage => _errorMessage;

  void dismiss() {
    _dismissTimer?.cancel();
    _phase = DownloadPhase.idle;
    _currentMediaId = null;
    _currentFileName = null;
    _progress = null;
    _receivedBytes = 0;
    _totalBytes = 0;
    _title = '';
    _detail = '';
    _savedPath = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<String?> startDownload({
    required MediaItem item,
    Uri? fileUri,
    String? authToken,
  }) async {
    if (isDownloading) return null;

    _dismissTimer?.cancel();
    final fileName = item.title.isNotEmpty
        ? item.title
        : (item.kind == MediaKind.video
            ? 'video_${item.id}.mp4'
            : 'photo_${item.id}.jpg');

    _currentMediaId = item.id;
    _currentFileName = fileName;
    _phase = DownloadPhase.connecting;
    _progress = null;
    _receivedBytes = 0;
    _totalBytes = 0;
    _title = 'Downloading $fileName';
    _detail = 'Connecting…';
    _savedPath = null;
    _errorMessage = null;
    notifyListeners();

    File? tempFile;
    try {
      final asset = item.asset;
      String? savedTempPath;

      if (!kIsWeb && File(asset).existsSync()) {
        _phase = DownloadPhase.downloading;
        _progress = 1.0;
        _detail = 'Reading local copy…';
        notifyListeners();
        savedTempPath = asset;
      } else if (fileUri != null) {
        final client = createHomeSpaceHttpClient();
        try {
          final req = http.Request('GET', fileUri);
          if (authToken != null && authToken.isNotEmpty) {
            req.headers['Authorization'] = 'Bearer $authToken';
          }
          final streamed =
              await client.send(req).timeout(const Duration(minutes: 10));
          if (streamed.statusCode != 200) {
            throw Exception('Server returned HTTP ${streamed.statusCode}');
          }

          final totalBytes = streamed.contentLength ?? 0;
          _totalBytes = totalBytes;
          _phase = DownloadPhase.downloading;
          var received = 0;

          final tempDir = await getTemporaryDirectory();
          final dlFile = File(
            '${tempDir.path}/dl_${item.id}_${DateTime.now().millisecondsSinceEpoch}_$fileName',
          );
          tempFile = dlFile;
          final sink = dlFile.openWrite();

          var lastUpdate = 0;
          try {
            await for (final chunk in streamed.stream) {
              sink.add(chunk);
              received += chunk.length;
              _receivedBytes = received;

              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - lastUpdate > 80 ||
                  (totalBytes > 0 && received >= totalBytes)) {
                lastUpdate = now;
                if (totalBytes > 0) {
                  _progress = (received / totalBytes).clamp(0.0, 1.0);
                  final pct = (_progress! * 100).round();
                  final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
                  final totMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
                  _detail = '$pct% • $recMb / $totMb MB';
                } else {
                  final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
                  _detail = '$recMb MB downloaded';
                }
                notifyListeners();
              }
            }
          } finally {
            await sink.flush();
            await sink.close();
          }

          if (received == 0) {
            throw Exception('No data received from server');
          }
          savedTempPath = dlFile.path;
        } finally {
          client.close();
        }
      } else if (asset.startsWith('assets/')) {
        _phase = DownloadPhase.downloading;
        _progress = 1.0;
        _detail = 'Loading asset…';
        notifyListeners();

        final data = await rootBundle.load(asset);
        final tempDir = await getTemporaryDirectory();
        final dlFile = File('${tempDir.path}/dl_${item.id}_$fileName');
        tempFile = dlFile;
        await dlFile.writeAsBytes(data.buffer.asUint8List());
        savedTempPath = dlFile.path;
      } else {
        throw Exception('Cannot locate media file to download');
      }

      _phase = DownloadPhase.saving;
      _progress = null;
      _title = 'Saving $fileName';
      _detail = 'Saving to device gallery…';
      notifyListeners();

      final isVideo = item.kind == MediaKind.video ||
          fileName.toLowerCase().endsWith('.mp4') ||
          fileName.toLowerCase().endsWith('.mov') ||
          fileName.toLowerCase().endsWith('.webm');
      final mimeType =
          lookupMimeType(fileName) ?? (isVideo ? 'video/mp4' : 'image/jpeg');

      final saved = await DeviceMediaService.saveMediaToDevice(
        filePath: savedTempPath,
        fileName: fileName,
        mimeType: mimeType,
      );

      _savedPath = saved;
      if (saved != null) {
        _phase = DownloadPhase.completed;
        _title = 'Saved to device gallery';
        _detail = fileName;
        _progress = 1.0;
        notifyListeners();

        _dismissTimer = Timer(const Duration(seconds: 4), () {
          dismiss();
        });
        return saved;
      } else {
        throw Exception('Failed to save to device storage');
      }
    } catch (e) {
      _phase = DownloadPhase.failed;
      _title = 'Download failed';
      _detail = e.toString().replaceFirst('Exception: ', '');
      _errorMessage = e.toString();
      notifyListeners();

      _dismissTimer = Timer(const Duration(seconds: 5), () {
        dismiss();
      });
      return null;
    } finally {
      if (tempFile != null && tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }
}
