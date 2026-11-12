import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import '../data/http_remote_repositories.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../pages/library_widgets.dart';
import '../pages/uploads_page.dart';
import 'frontend_session.dart';
import 'home_scope.dart';

class PhotoPickerHelper {
  static final ImagePicker _picker = ImagePicker();

  static Future<void> showAddOptions(
    BuildContext context, {
    String? targetAlbumId,
  }) async {
    final repository = HomeScope.of(context);
    final session = FrontendSessionScope.maybeOf(context);

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withAlpha(80),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  targetAlbumId != null ? 'Add to Album' : 'Add Memories',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F5E9),
                    foregroundColor: Color(0xFF2E7D32),
                    child: Icon(Icons.photo_library_rounded),
                  ),
                  title: const Text('Choose from gallery'),
                  subtitle: const Text('Upload photos from this device'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    pickFromGallery(
                      context,
                      repository: repository,
                      session: session,
                      targetAlbumId: targetAlbumId,
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE3F2FD),
                    foregroundColor: Color(0xFF1565C0),
                    child: Icon(Icons.camera_alt_rounded),
                  ),
                  title: const Text('Take a photo'),
                  subtitle: const Text('Capture a moment right now'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    takePhoto(
                      context,
                      repository: repository,
                      session: session,
                      targetAlbumId: targetAlbumId,
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFF3E0),
                    foregroundColor: Color(0xFFE65100),
                    child: Icon(Icons.videocam_rounded),
                  ),
                  title: const Text('Choose video'),
                  subtitle: const Text('Upload a short clip'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    pickVideo(
                      context,
                      repository: repository,
                      session: session,
                      targetAlbumId: targetAlbumId,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> pickFromGallery(
    BuildContext context, {
    required HomeRepository repository,
    FrontendSession? session,
    String? targetAlbumId,
  }) async {
    try {
      final images = await _picker.pickMultiImage();
      if (images.isEmpty) return;

      if (!context.mounted) return;
      _processFiles(
        context,
        files: images,
        repository: repository,
        session: session,
        kind: MediaKind.photo,
        category: 'Gallery',
        targetAlbumId: targetAlbumId,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick photos: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  static Future<void> takePhoto(
    BuildContext context, {
    required HomeRepository repository,
    FrontendSession? session,
    String? targetAlbumId,
  }) async {
    try {
      final photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null) return;

      if (!context.mounted) return;
      _processFiles(
        context,
        files: [photo],
        repository: repository,
        session: session,
        kind: MediaKind.photo,
        category: 'Camera',
        targetAlbumId: targetAlbumId,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Camera error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  static Future<void> pickVideo(
    BuildContext context, {
    required HomeRepository repository,
    FrontendSession? session,
    String? targetAlbumId,
  }) async {
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;

      if (!context.mounted) return;
      _processFiles(
        context,
        files: [video],
        repository: repository,
        session: session,
        kind: MediaKind.video,
        category: 'Videos',
        targetAlbumId: targetAlbumId,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Video picker error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  static Future<void> _processFiles(
    BuildContext context, {
    required List<XFile> files,
    required HomeRepository repository,
    FrontendSession? session,
    required MediaKind kind,
    required String category,
    String? targetAlbumId,
  }) async {
    final serverUri = session?.serverUri;
    final token = session?.authToken;
    final isOnlineServer = serverUri != null && token != null && repository.uploads is HttpUploadRepository;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Text(
          isOnlineServer
              ? 'Uploading ${files.length} ${files.length == 1 ? 'memory' : 'memories'} to your home server…'
              : 'Adding ${files.length} ${files.length == 1 ? 'memory' : 'memories'} to your library…',
        ),
        action: SnackBarAction(
          label: 'View Queue',
          onPressed: () {
            messenger.clearSnackBars();
            openSpacePage<void>(context, const UploadsPage());
          },
        ),
      ),
    );

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final bytes = await file.readAsBytes();
      final filename = file.name;
      final mimeType = lookupMimeType(filename) ?? (kind == MediaKind.video ? 'video/mp4' : 'image/jpeg');

      if (isOnlineServer) {
        final uploadRepo = repository.uploads as HttpUploadRepository;
        final uploadId = 'up-${DateTime.now().microsecondsSinceEpoch}-$i';
        uploadRepo.queueUpload(
          id: uploadId,
          mediaId: uploadId,
          totalBytes: bytes.length,
          bytes: bytes,
          filename: filename,
          mimeType: mimeType,
          targetAlbumId: targetAlbumId,
        );
      } else {
        final item = MediaItem(
          id: 'media-${DateTime.now().microsecondsSinceEpoch}-$i',
          asset: file.path,
          title: filename,
          category: category,
          takenAt: DateTime.now(),
          kind: kind,
        );
        await repository.addMedia(item);
        if (targetAlbumId != null) {
          try {
            await repository.addToAlbum(targetAlbumId, item.id);
          } catch (_) {}
        }
      }
    }
  }
}
