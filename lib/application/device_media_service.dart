import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class DeviceMediaService {
  static const _mediaChannel = MethodChannel('com.homespace.homespace/media_saver');
  static const _permissionChannel = MethodChannel('com.homespace.homespace/permissions');

  @visibleForTesting
  static bool debugOverrideIsAndroid = false;

  /// Saves photo or video bytes directly into the public Android MediaStore (Pictures/HomeSpace or Movies/HomeSpace),
  /// or Downloads folder on Desktop.
  static Future<String?> saveMediaToDevice({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (kIsWeb) return null;

    if (Platform.isAndroid || debugOverrideIsAndroid) {
      try {
        final result = await _mediaChannel.invokeMethod<String>('saveMedia', {
          'bytes': Uint8List.fromList(bytes),
          'fileName': fileName,
          'mimeType': mimeType,
        });
        return result;
      } catch (e) {
        debugPrint('DeviceMediaService: saveMedia error $e');
      }
    }

    // Fallback for desktop / other platforms
    try {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Checks if photo/video reading permission is granted.
  static Future<bool> checkStoragePermission() async {
    if (kIsWeb || (!Platform.isAndroid && !debugOverrideIsAndroid)) return true;
    try {
      final granted = await _permissionChannel.invokeMethod<bool>('checkStoragePermission');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Requests photo/video reading permission from the user via Android system prompt.
  static Future<bool> requestStoragePermission() async {
    if (kIsWeb || (!Platform.isAndroid && !debugOverrideIsAndroid)) return true;
    try {
      final granted = await _permissionChannel.invokeMethod<bool>('requestStoragePermission');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Queries all camera photos and videos directly from the native Android MediaStore.
  static Future<List<Map<String, dynamic>>> queryCameraMedia() async {
    if (kIsWeb || (!Platform.isAndroid && !debugOverrideIsAndroid)) return const [];
    try {
      final list = await _permissionChannel.invokeListMethod<Map>('queryCameraMedia');
      if (list == null) return const [];
      return list.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (_) {
      return const [];
    }
  }
}
