import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../application/device_media_service.dart';
import '../application/frontend_session.dart';
import '../application/home_scope.dart';
import '../data/homespace_api_client.dart';
import '../design/album_widgets.dart';
import '../design/photo_action.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../design/system_ui.dart';
import '../domain/models.dart';
import 'album_page.dart';
import 'library_widgets.dart';
import 'local_edit_sheets.dart';

String _photoTime(DateTime value) {
  final date = value.toLocal();
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  return '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'AM' : 'PM'}';
}

class BundledPhotoMetadata {
  final int bytes;
  final int width;
  final int height;
  const BundledPhotoMetadata(this.bytes, this.width, this.height);
  String get fileSize => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} KB';
}

bool _hasImageMagicBytes(Uint8List bytes) {
  if (bytes.length < 4) return false;
  // JPEG: FF D8
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
  // PNG: 89 50 4E 47
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
  // GIF: 47 49 46
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
  // WebP: RIFF ... WEBP
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
      bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
    return true;
  }
  // BMP: 42 4D
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true;
  return false;
}

Future<BundledPhotoMetadata> readBundledPhotoMetadata(
  String asset, {
  MediaKind? kind,
}) async {
  if (asset.startsWith('http://') || asset.startsWith('https://')) {
    return const BundledPhotoMetadata(0, 0, 0);
  }
  final isVideo = kind == MediaKind.video ||
      asset.toLowerCase().endsWith('.mp4') ||
      asset.toLowerCase().endsWith('.mov') ||
      asset.toLowerCase().endsWith('.mkv') ||
      asset.toLowerCase().endsWith('.avi');

  if (!kIsWeb && File(asset).existsSync()) {
    try {
      final file = File(asset);
      final len = file.lengthSync();
      if (isVideo) {
        return BundledPhotoMetadata(len, 0, 0);
      }
      final bytes = await file.readAsBytes();
      if (!_hasImageMagicBytes(bytes)) {
        return BundledPhotoMetadata(len, 0, 0);
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          return BundledPhotoMetadata(
            len,
            descriptor.width,
            descriptor.height,
          );
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } catch (_) {
      try {
        final len = File(asset).lengthSync();
        return BundledPhotoMetadata(len, 0, 0);
      } catch (_) {
        return const BundledPhotoMetadata(0, 0, 0);
      }
    }
  }

  // Bundled asset path (e.g. assets/photos/photo_01.jpg)
  try {
    if (isVideo) {
      return const BundledPhotoMetadata(0, 0, 0);
    }
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (!_hasImageMagicBytes(bytes)) {
      return BundledPhotoMetadata(bytes.lengthInBytes, 0, 0);
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        return BundledPhotoMetadata(
          bytes.lengthInBytes,
          descriptor.width,
          descriptor.height,
        );
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  } catch (_) {
    return const BundledPhotoMetadata(0, 0, 0);
  }
}

Future<void> openMediaViewer(
  BuildContext context, {
  required List<String> mediaIds,
  required String initialId,
  bool inTrash = false,
}) => openSpacePage<void>(
  context,
  MediaViewer(
    mediaIds: List.unmodifiable(mediaIds),
    initialId: initialId,
    inTrash: inTrash,
  ),
);

class MediaViewer extends StatefulWidget {
  final List<String> mediaIds;
  final String initialId;
  final bool inTrash;
  const MediaViewer({
    super.key,
    required this.mediaIds,
    required this.initialId,
    this.inTrash = false,
  });

  static void clearLocalCaches() {
    _PhotoViewerView.clearLocalPathCache();
  }

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late int index = widget.mediaIds
      .indexOf(widget.initialId)
      .clamp(0, widget.mediaIds.isEmpty ? 0 : widget.mediaIds.length - 1);
  late final controller = PageController(initialPage: index);
  final viewportKey = GlobalKey<_PhotoViewportState>();
  Drag? pageDrag;
  int? dragOrigin;
  bool zoomed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchNeighbors(index);
    });
  }

  void _prefetchNeighbors(int currentIndex) {
    if (!mounted || widget.mediaIds.isEmpty) return;
    try {
      final repository = HomeScope.of(context);
      final token = FrontendSessionScope.maybeOf(context)?.authToken;
      final authHeaders = token != null ? {'Authorization': 'Bearer $token'} : null;

      // Prefetch current and adjacent photos in full resolution (Google Photos predictive pre-caching)
      final session = FrontendSessionScope.maybeOf(context);
      final offsets = [0, 1, -1];
      for (final offset in offsets) {
        final targetIndex = currentIndex + offset;
        if (targetIndex >= 0 && targetIndex < widget.mediaIds.length) {
          final id = widget.mediaIds[targetIndex];
          final item = repository.mediaById(id);
          if (item != null && item.kind == MediaKind.photo) {
            final previewUri = resolveMediaUri(
              asset: item.asset,
              id: item.id,
              serverUri: session?.serverUri,
              endpoint: 'preview',
            );
            if (previewUri != null) {
              precacheImage(
                NetworkImage(previewUri.toString(), headers: authHeaders),
                context,
              );
            }
          }
        }
      }
    } catch (_) {
      // In case context is unmounted or repository is not available in unit tests
    }
  }

  @override
  void dispose() {
    pageDrag?.cancel();
    controller.dispose();
    super.dispose();
  }

  void startPageDrag(DragStartDetails details) {
    cancelPageDrag();
    if (!controller.hasClients) return;
    dragOrigin = index;
    late final Drag drag;
    drag = controller.position.drag(details, () {
      if (identical(pageDrag, drag)) pageDrag = null;
    });
    pageDrag = drag;
  }

  void updatePageDrag(DragUpdateDetails details) => pageDrag?.update(details);

  void endPageDrag(DragEndDetails details) {
    dragOrigin = null;
    final drag = pageDrag;
    pageDrag = null;
    drag?.end(details);
  }

  void cancelPageDrag() {
    final origin = dragOrigin;
    dragOrigin = null;
    final drag = pageDrag;
    pageDrag = null;
    drag?.cancel();
    if (origin != null && controller.hasClients) controller.jumpToPage(origin);
  }

  void changePage(int next) {
    viewportKey.currentState?.reset();
    setState(() {
      index = next;
      zoomed = false;
    });
    _prefetchNeighbors(next);
  }

  void step(int amount) {
    if (!controller.hasClients) return;
    final next = (index + amount).clamp(0, widget.mediaIds.length - 1);
    if (next == index) return;
    viewportKey.currentState?.reset();
    final duration = spaceMotion(context, 220);
    if (duration == Duration.zero) {
      controller.jumpToPage(next);
    } else {
      controller.animateToPage(
        next,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _dateLabel(DateTime value) {
    final date = value.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final id = widget.mediaIds.isEmpty ? null : widget.mediaIds[index];
    final photo = id == null ? null : repository.mediaById(id);
    final trashed = repository.trash.any((item) => item.mediaId == id);
    final available = photo != null && trashed == widget.inTrash;
    final busy = repository.pendingWrites > 0;
    return Theme(
      data: spaceTheme(Brightness.dark, SpacePage.photos),
      child: Builder(
        builder: (context) {
          final text = Theme.of(context).textTheme;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: spaceSystemUiStyle(
              context,
              backgroundColor: const Color(0xFF101519),
            ),
            child: Scaffold(
              backgroundColor: const Color(0xFF101519),
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  final top = 56 + 28 * (scale.clamp(1.0, 2.0).toDouble() - 1);
                  final bottom =
                      88 + 32 * (scale.clamp(1.0, 2.0).toDouble() - 1);
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: top + MediaQuery.paddingOf(context).top,
                            bottom:
                                bottom + MediaQuery.paddingOf(context).bottom,
                          ),
                          child: _PhotoViewport(
                            key: viewportKey,
                            label: photo?.title ?? 'Unavailable memory',
                            canZoom: available && photo.kind == MediaKind.photo,
                            onSwipeUp: photo == null ? null : () => _showDetails(context, photo),
                            onSwipeDown: () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              }
                            },
                            onPageDragStart: startPageDrag,
                            onPageDragUpdate: updatePageDrag,
                            onPageDragEnd: endPageDrag,
                            onPageDragCancel: cancelPageDrag,
                            onZoom: (value) {
                              if (mounted && zoomed != value) {
                                setState(() => zoomed = value);
                              }
                            },
                            child: widget.mediaIds.isEmpty
                                ? const Center(
                                    child: Text('This memory is unavailable'),
                                  )
                                : PageView.builder(
                                    key: const ValueKey('viewer-pages'),
                                    controller: controller,
                                    // One viewport recognizer coordinates all
                                    // photos, including a second finger landing
                                    // on the neighboring page during a swipe.
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    onPageChanged: changePage,
                                    itemCount: widget.mediaIds.length,
                                    itemBuilder: (context, page) {
                                      final item = repository.mediaById(
                                        widget.mediaIds[page],
                                      );
                                      final isTrashed = repository.trash.any(
                                        (entry) => entry.mediaId == item?.id,
                                      );
                                      if (item == null ||
                                          isTrashed != widget.inTrash) {
                                        return const Center(
                                          child: Text(
                                            'This memory is unavailable',
                                          ),
                                        );
                                      }
                                      if (item.kind == MediaKind.video) {
                                        return _VideoPlayerView(
                                          key: ValueKey('video-${item.id}'),
                                          item: item,
                                          active: page == index,
                                        );
                                      }
                                      return _PhotoViewerView(
                                        key: ValueKey('photo-${item.id}'),
                                        item: item,
                                        zoomed: zoomed && page == index,
                                        active: page == index,
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _controls(
                          SafeArea(
                            bottom: false,
                            child: SizedBox(
                              height: top,
                              child: Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Close viewer',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.arrow_back_rounded),
                                  ),
                                  Expanded(
                                    child: Semantics(
                                      key: const ValueKey('viewer-position'),

                                      liveRegion: true,
                                      label:
                                          '${photo?.title ?? 'Unavailable memory'}, ${widget.mediaIds.isEmpty ? 0 : index + 1} of ${widget.mediaIds.length} memories',
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (photo != null) ...[
                                            Text(
                                              _dateLabel(photo.takenAt),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: text.labelLarge,
                                            ),
                                            Text(
                                              _photoTime(photo.takenAt),
                                              style: text.bodyMedium!.copyWith(
                                                fontSize: 12,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    key: const ValueKey('viewer-share'),
                                    icon: const Icon(Icons.share_rounded),
                                    tooltip: 'Share memory',
                                    onPressed: photo == null ? null : () => _shareMedia(context, photo),
                                  ),
                                  IconButton(
                                    key: const ValueKey('viewer-download'),
                                    icon: const Icon(Icons.download_rounded),
                                    tooltip: 'Download to device',
                                    onPressed: photo == null ? null : () => _downloadMedia(context, photo),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'More photo options',
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        enabled: false,
                                        child: Text(
                                          '${widget.mediaIds.isEmpty ? 0 : index + 1} / ${widget.mediaIds.length}',
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'share',
                                        enabled: photo != null,
                                        child: const Tooltip(
                                          message: 'Share memory',
                                          child: Text('Share memory'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'download',
                                        enabled: photo != null,
                                        child: const Tooltip(
                                          message: 'Download to device',
                                          child: Text('Download original'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'previous',
                                        enabled: index > 0,
                                        child: const Tooltip(
                                          message: 'Previous photo',
                                          child: Text('Previous photo'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'next',
                                        enabled:
                                            index < widget.mediaIds.length - 1,
                                        child: const Tooltip(
                                          message: 'Next photo',
                                          child: Text('Next photo'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'zoom',
                                        enabled:
                                            available &&
                                            photo.kind == MediaKind.photo,
                                        child: Tooltip(
                                          message: zoomed
                                              ? 'Reset zoom'
                                              : 'Zoom in',
                                          child: Text(
                                            zoomed ? 'Reset zoom' : 'Zoom in',
                                          ),
                                        ),
                                      ),
                                    ],
                                    onSelected: (action) {
                                      if (action == 'share' && photo != null) {
                                        _shareMedia(context, photo);
                                      }
                                      if (action == 'download' && photo != null) {
                                        _downloadMedia(context, photo);
                                      }
                                      if (action == 'previous') step(-1);
                                      if (action == 'next') step(1);
                                      if (action == 'zoom' && photo != null) {
                                        viewportKey.currentState?.toggle();
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (available)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _controls(
                            SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.inTrash) ...[
                                      Expanded(
                                        child: PhotoAction(
                                          key: const ValueKey('restore-memory'),
                                          label: 'Restore',
                                          tooltip: 'Restore memory',
                                          icon: Icons.restore_rounded,
                                          onPressed: busy
                                              ? null
                                              : () async {
                                                  final saved =
                                                      await saveLocalChange(
                                                        context,
                                                        () => repository
                                                            .restore(photo.id),
                                                      );
                                                  if (saved &&
                                                      context.mounted) {
                                                    popSpaceRouteIfCurrent(
                                                      context,
                                                    );
                                                  }
                                                },
                                        ),
                                      ),
                                      Expanded(
                                        child: PhotoAction(
                                          key: const ValueKey('delete-memory'),
                                          label: 'Delete',
                                          tooltip: 'Delete memory permanently',
                                          icon: Icons.delete_forever_outlined,
                                          onPressed: busy
                                              ? null
                                              : () async {
                                                  final saved =
                                                      await deleteTrashedMemories(
                                                        context,
                                                        [photo.id],
                                                      );
                                                  if (saved &&
                                                      context.mounted) {
                                                    popSpaceRouteIfCurrent(
                                                      context,
                                                    );
                                                  }
                                                },
                                        ),
                                      ),
                                      Expanded(
                                        child: PhotoAction(
                                          key: const ValueKey('download-trash-memory'),
                                          label: 'Download',
                                          tooltip: 'Download to device',
                                          icon: Icons.download_rounded,
                                          onPressed: () => _downloadMedia(context, photo),
                                        ),
                                      ),
                                      Expanded(
                                        child: PhotoAction(
                                          label: 'Info',
                                          tooltip: 'Photo details',
                                          icon: Icons.info_outline_rounded,
                                          onPressed: () =>
                                              _showDetails(context, photo),
                                        ),
                                      ),
                                    ] else ...[
                                      Expanded(
                                        child: PhotoAction(
                                          key: const ValueKey(
                                            'toggle-favorite',
                                          ),
                                          label: 'Favorite',
                                          tooltip:
                                              repository.favorites.contains(
                                                photo.id,
                                              )
                                              ? 'Remove from favorites'
                                              : 'Add to favorites',
                                          selected: repository.favorites
                                              .contains(photo.id),
                                          icon:
                                              repository.favorites.contains(
                                                photo.id,
                                              )
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_border_rounded,
                                          onPressed: busy
                                              ? null
                                              : () => saveLocalChange(
                                                  context,
                                                  () => repository
                                                      .toggleFavorite(photo.id),
                                                ),
                                        ),
                                      ),
                                      Expanded(
                                        child: PhotoAction(
                                          key: const ValueKey('choose-album'),
                                          label: 'Add to album',
                                          tooltip: 'Add to albums',
                                          icon: Icons
                                              .add_photo_alternate_outlined,
                                          onPressed: busy
                                              ? null
                                              : () => showSpaceSheet<bool>(
                                                  context,
                                                  AlbumPickerSheet(
                                                    mediaIds: [photo.id],
                                                  ),
                                                ),
                                        ),
                                      ),
                                      Expanded(
                                        child: PhotoAction(
                                          key: const ValueKey('download-memory'),
                                          label: 'Download',
                                          tooltip: 'Download to device',
                                          icon: Icons.download_rounded,
                                          onPressed: () => _downloadMedia(context, photo),
                                        ),
                                      ),
                                      Expanded(
                                        child: PhotoAction(
                                          label: 'Info',
                                          tooltip: 'Photo details',
                                          icon: Icons.info_outline_rounded,
                                          onPressed: () =>
                                              _showDetails(context, photo),
                                        ),
                                      ),
                                      Expanded(
                                        child: PhotoAction(
                                          key: const ValueKey('trash-memory'),
                                          label: 'Trash',
                                          tooltip: 'Move to Trash',
                                          icon: Icons.delete_outline_rounded,
                                          onPressed: busy
                                              ? null
                                              : () async {
                                                  final saved =
                                                      await trashMemories(
                                                        context,
                                                        [photo.id],
                                                      );
                                                  if (saved &&
                                                      context.mounted) {
                                                    popSpaceRouteIfCurrent(
                                                      context,
                                                    );
                                                  }
                                                },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _downloadMedia(BuildContext context, MediaItem photo) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Downloading ${photo.title}…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final List<int> bytes;
      final asset = photo.asset;
      final fileName = photo.title.isNotEmpty
          ? photo.title
          : (photo.kind == MediaKind.video ? 'video_${photo.id}.mp4' : 'photo_${photo.id}.jpg');

      final session = FrontendSessionScope.maybeOf(context);
      final fileUri = resolveMediaUri(
        asset: asset,
        id: photo.id,
        serverUri: session?.serverUri,
        endpoint: 'file',
      );

      if (!kIsWeb && File(asset).existsSync()) {
        bytes = await File(asset).readAsBytes();
      } else if (fileUri != null) {
        final token = session?.authToken;
        final client = createHomeSpaceHttpClient();
        try {
          final response = await client.get(
            fileUri,
            headers: token != null ? {'Authorization': 'Bearer $token'} : null,
          ).timeout(const Duration(minutes: 5));

          if (response.statusCode == 200) {
            bytes = response.bodyBytes;
          } else {
            throw Exception('Server returned ${response.statusCode}');
          }
        } finally {
          client.close();
        }
      } else if (asset.startsWith('assets/')) {
        final data = await rootBundle.load(asset);
        bytes = data.buffer.asUint8List();
      } else {
        throw Exception('Cannot locate media file to download');
      }

      if (bytes.isEmpty) {
        throw Exception('No data received');
      }

      final isVideo = photo.kind == MediaKind.video ||
          fileName.toLowerCase().endsWith('.mp4') ||
          fileName.toLowerCase().endsWith('.mov') ||
          fileName.toLowerCase().endsWith('.webm');
      final mimeType = lookupMimeType(fileName) ?? (isVideo ? 'video/mp4' : 'image/jpeg');

      final savedPath = await DeviceMediaService.saveMediaToDevice(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );

      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();

      if (savedPath != null) {
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Saved to device gallery ($fileName)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not save $fileName to device storage.'),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Download failed: $e'),
        ),
      );
    }
  }

  Future<void> _shareMedia(BuildContext context, MediaItem photo) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    if (!kIsWeb && File(photo.asset).existsSync()) {
      final shared = await DeviceMediaService.shareMedia(
        filePath: photo.asset,
        mimeType: photo.kind == MediaKind.video ? 'video/*' : 'image/*',
      );
      if (shared) return;
    }

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Sharing "${photo.title}"…'),
      ),
    );
  }

  Widget _controls(Widget child) =>
      ColoredBox(color: const Color(0xF5101519), child: child);

  bool _showingDetails = false;

  void _showDetails(BuildContext context, MediaItem photo) {
    if (_showingDetails || !mounted) return;
    _showingDetails = true;
    final repository = HomeScope.of(context);
    final date = photo.takenAt.toLocal();
    final albums = repository.albums.where(
      (album) => album.mediaIds.contains(photo.id),
    );
    final metadata = readBundledPhotoMetadata(photo.asset, kind: photo.kind);
    final contributors = {for (final album in albums) album.addedBy[photo.id]}
        .whereType<String>()
        .toList();
    final appearance = repository.profile.appearance;
    final brightness = switch (appearance) {
      Appearance.light => Brightness.light,
      Appearance.dark => Brightness.dark,
      Appearance.system => MediaQuery.platformBrightnessOf(context),
    };
    final theme = spaceTheme(brightness, SpacePage.collections);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) => Theme(
        data: theme,
        child: Material(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Photo details',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close photo details',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date & time',
                    value: '${_dateLabel(date)} · ${_photoTime(date)}',
                  ),
                  const Divider(height: 1),
                  FutureBuilder<BundledPhotoMetadata>(
                    future: metadata,
                    builder: (context, result) => _DetailRow(
                      icon: Icons.insert_drive_file_outlined,
                      label: 'Filename',
                      value: photo.asset.split('/').last,
                      note: result.hasData && result.data!.bytes > 0
                          ? (result.data!.width > 0 && result.data!.height > 0)
                              ? '${result.data!.fileSize} · ${result.data!.width} × ${result.data!.height}'
                              : (photo.formattedDuration != null
                                  ? '${result.data!.fileSize} · ${photo.formattedDuration}'
                                  : result.data!.fileSize)
                          : result.hasError
                          ? 'File details unavailable'
                          : 'Reading file details…',
                    ),
                  ),
                  const Divider(height: 1),
                  _DetailRow(
                    icon: photo.isSynced
                        ? Icons.cloud_done_rounded
                        : Icons.phone_android_rounded,
                    label: 'Storage & sync',
                    value: photo.isSynced
                        ? 'Synced to Home Server ☁️'
                        : 'Stored locally on this device 📱',
                    note: photo.isSynced
                        ? 'Protected in private family cloud'
                        : 'Ready to back up to your server',
                  ),
                  const Divider(height: 1),
                  Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(
                          Icons.photo_album_outlined,
                          color: Color(0xFFA560F5),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Albums', style: theme.textTheme.labelLarge),
                              const SizedBox(height: 7),
                              if (albums.isEmpty)
                                Text(
                                  'Not in an album',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              for (final album in albums)
                                InkWell(
                                  onTap: () => openSpacePage<void>(
                                    context,
                                    AlbumPage(albumId: album.id),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: SizedBox(
                                            width: 28,
                                            height: 24,
                                            child:
                                                repository.coverFor(album) ==
                                                    null
                                                ? const Icon(
                                                    Icons.photo_outlined,
                                                  )
                                                : MediaThumbnail(
                                                    media: repository.coverFor(
                                                      album,
                                                    )!,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            album.title,
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 19,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  _DetailRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Added by',
                    value: contributors.isEmpty
                        ? 'Not recorded'
                        : contributors
                              .map((id) => repository.memberById(id).name)
                              .join(', '),
                    leading: contributors.isEmpty
                        ? null
                        : AlbumPeople(
                            members: contributors
                                .map(repository.memberById)
                                .toList(),
                          ),
                    note: contributors.isEmpty ? null : 'Album contributors',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) {
        _showingDetails = false;
      }
    });
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final Widget? leading;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
    this.leading,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = SpaceStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading ??
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: style.accentInk, size: 21),
              ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(value, style: theme.textTheme.bodyMedium),
                if (note != null)
                  Text(
                    note!,
                    style: theme.textTheme.bodyMedium!.copyWith(fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoViewport extends StatefulWidget {
  final Widget child;
  final String label;
  final bool canZoom;
  final ValueChanged<bool> onZoom;
  final GestureDragStartCallback onPageDragStart;
  final GestureDragUpdateCallback onPageDragUpdate;
  final GestureDragEndCallback onPageDragEnd;
  final GestureDragCancelCallback onPageDragCancel;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  const _PhotoViewport({
    super.key,
    required this.child,
    required this.label,
    required this.canZoom,
    required this.onZoom,
    required this.onPageDragStart,
    required this.onPageDragUpdate,
    required this.onPageDragEnd,
    required this.onPageDragCancel,
    this.onSwipeUp,
    this.onSwipeDown,
  });
  @override
  State<_PhotoViewport> createState() => _PhotoViewportState();
}

class _PhotoViewportState extends State<_PhotoViewport>
    with SingleTickerProviderStateMixin {
  final transform = TransformationController();
  late final animation = AnimationController(vsync: this)..addListener(_tick);
  Animation<Matrix4>? tween;
  Offset? tapped;
  Size size = Size.zero;
  bool zoomed = false;
  final pointers = <int>{};
  bool multiplePointers = false;
  bool startedZoomed = false;
  bool paging = false;
  Offset? swipeStart;

  void cancelPaging() {
    if (!paging) return;
    paging = false;
    widget.onPageDragCancel();
  }

  void pointerDown(PointerDownEvent event) {
    if (pointers.isEmpty) {
      multiplePointers = false;
      startedZoomed = zoomed;
      swipeStart = null;
    }
    pointers.add(event.pointer);
    if (pointers.length > 1) {
      multiplePointers = true;
      cancelPaging();
    }
  }

  void interactionStart(ScaleStartDetails details) {
    animation.stop();
    swipeStart = details.focalPoint;
  }

  void interactionUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1 || zoomed) {
      multiplePointers |= details.pointerCount > 1;
      startedZoomed |= zoomed;
      cancelPaging();
      return;
    }
    // A pinch stays a photo gesture until every finger is lifted, including
    // when it ends at 1x. A fresh one-finger drag then pages normally.
    if (multiplePointers || startedZoomed) return;
    final delta = details.focalPoint - (swipeStart ?? details.focalPoint);
    if (!paging &&
        !zoomed &&
        !multiplePointers &&
        delta.dy < -50 &&
        delta.dy.abs() > delta.dx.abs() * 1.8 &&
        widget.onSwipeUp != null) {
      swipeStart = null;
      widget.onSwipeUp!();
      return;
    }
    if (!paging &&
        !zoomed &&
        !multiplePointers &&
        delta.dy > 50 &&
        delta.dy.abs() > delta.dx.abs() * 1.8 &&
        widget.onSwipeDown != null) {
      swipeStart = null;
      widget.onSwipeDown!();
      return;
    }
    if (!paging && delta.dx.abs() > 8 && delta.dx.abs() > delta.dy.abs()) {
      paging = true;
      widget.onPageDragStart(
        DragStartDetails(
          globalPosition: details.focalPoint,
          localPosition: details.localFocalPoint,
        ),
      );
    }
    if (paging) {
      widget.onPageDragUpdate(
        DragUpdateDetails(
          delta: Offset(details.focalPointDelta.dx, 0),
          primaryDelta: details.focalPointDelta.dx,
          globalPosition: details.focalPoint,
          localPosition: details.localFocalPoint,
        ),
      );
    }
  }

  void interactionEnd(ScaleEndDetails details) {
    if (!paging) return;
    if (details.pointerCount > 0 || multiplePointers) {
      cancelPaging();
      return;
    }
    paging = false;
    widget.onPageDragEnd(
      DragEndDetails(
        velocity: Velocity(
          pixelsPerSecond: Offset(details.velocity.pixelsPerSecond.dx, 0),
        ),
        primaryVelocity: details.velocity.pixelsPerSecond.dx,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    transform.addListener(() {
      final next = transform.value.getMaxScaleOnAxis() > 1.01;
      if (next != zoomed) {
        setState(() => zoomed = next);
        widget.onZoom(next);
      }
    });
  }

  void _tick() {
    if (tween != null) transform.value = tween!.value;
  }

  void reset() {
    animation.stop();
    transform.value = Matrix4.identity();
  }

  void toggle({Offset? at}) {
    final point = at ?? Offset(size.width / 2, size.height / 2);
    final target = zoomed
        ? Matrix4.identity()
        : (Matrix4.diagonal3Values(2.5, 2.5, 1)
            ..setTranslationRaw(-point.dx * 1.5, -point.dy * 1.5, 0));
    animation.duration = spaceMotion(context, 180);
    tween = Matrix4Tween(
      begin: transform.value.clone(),
      end: target,
    ).animate(animation.drive(CurveTween(curve: Curves.easeOutCubic)));
    animation.forward(from: 0);
  }

  @override
  void dispose() {
    animation.dispose();
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      size = constraints.biggest;
      return Semantics(
        label: widget.label,
        child: ExcludeSemantics(
          child: Listener(
            onPointerDown: pointerDown,
            onPointerUp: (event) => pointers.remove(event.pointer),
            onPointerCancel: (event) {
              pointers.remove(event.pointer);
              cancelPaging();
            },
            child: GestureDetector(
              onDoubleTapDown: widget.canZoom
                  ? (details) => tapped = details.localPosition
                  : null,
              onDoubleTap: widget.canZoom ? () => toggle(at: tapped) : null,
              child: InteractiveViewer(
                transformationController: transform,
                minScale: 1,
                maxScale: 4,
                scaleEnabled: widget.canZoom,
                // One recognizer owns the whole pointer sequence. PageView's
                // horizontal recognizer must not reject a later second finger.
                panEnabled: true,
                onInteractionStart: interactionStart,
                onInteractionUpdate: interactionUpdate,
                onInteractionEnd: interactionEnd,
                child: SizedBox.expand(child: widget.child),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _PhotoViewerView extends StatefulWidget {
  final MediaItem item;
  final bool zoomed;
  final bool active;
  const _PhotoViewerView({
    super.key,
    required this.item,
    this.zoomed = false,
    this.active = true,
  });

  static void clearLocalPathCache() {
    _PhotoViewerViewState.clearLocalPathCache();
  }

  @override
  State<_PhotoViewerView> createState() => _PhotoViewerViewState();
}

class _PhotoViewerViewState extends State<_PhotoViewerView> {
  static final Map<String, String?> _localPathCache = {};
  static final Map<String, String?> _diskPreviewCache = {};
  static final Set<String> _inFlightDownloads = {};

  static void clearLocalPathCache() {
    _localPathCache.clear();
  }

  String? _resolvedPath;
  String? _fallbackThumbPath;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _resolvePhoto();
  }

  @override
  void didUpdateWidget(covariant _PhotoViewerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.asset != widget.item.asset) {
      _hasError = false;
      _resolvedPath = null;
      _fallbackThumbPath = null;
      _resolvePhoto();
    }
  }

  Future<void> _resolvePhoto() async {
    final asset = widget.item.asset;
    final title = widget.item.title.trim();
    final id = widget.item.id;

    // 1. Direct local file on disk
    if (!kIsWeb && !asset.startsWith('http://') && !asset.startsWith('https://')) {
      if (File(asset).existsSync() && File(asset).lengthSync() > 0) {
        if (mounted) setState(() => _resolvedPath = asset);
        return;
      }
    }

    // 2. Bundled assets
    if (asset.startsWith('assets/')) {
      if (mounted) setState(() => _resolvedPath = asset);
      return;
    }

    if (kIsWeb) return;

    // 3. Search local device storage via native MediaStore for instant 0ms full-res photo
    if (title.isNotEmpty) {
      if (_localPathCache.containsKey(title)) {
        final cached = _localPathCache[title];
        if (cached != null && File(cached).existsSync() && File(cached).lengthSync() > 0) {
          if (mounted) setState(() => _resolvedPath = cached);
          return;
        } else {
          _localPathCache.remove(title);
        }
      }
      final local = await DeviceMediaService.findLocalMedia(title, isVideo: false);
      if (local != null && File(local).existsSync() && File(local).lengthSync() > 0) {
        _localPathCache[title] = local;
        if (mounted) setState(() => _resolvedPath = local);
        return;
      } else {
        _localPathCache.remove(title);
      }
    }

    // 4. Check persistent disk cache (preview, full photo, or thumbnail from grid)
    try {
      final tempDir = await getTemporaryDirectory();
      final previewCache = File('${tempDir.path}/preview_$id.webp');
      final thumbCache = File('${tempDir.path}/thumb_$id.webp');

      if (_diskPreviewCache.containsKey(id)) {
        final cached = _diskPreviewCache[id];
        if (cached != null && File(cached).existsSync() && File(cached).lengthSync() > 0) {
          if (mounted) setState(() => _resolvedPath = cached);
          return;
        } else {
          _diskPreviewCache.remove(id);
        }
      }

      if (previewCache.existsSync() && previewCache.lengthSync() > 0) {
        _diskPreviewCache[id] = previewCache.path;
        if (mounted) setState(() => _resolvedPath = previewCache.path);
        return;
      }

      // If thumbnail was already downloaded by grid, show it immediately so screen is NEVER black!
      if (thumbCache.existsSync() && thumbCache.lengthSync() > 0) {
        if (mounted) setState(() => _fallbackThumbPath = thumbCache.path);
      }

      // 5. Download preview from network & cache to disk
      final session = mounted ? FrontendSessionScope.maybeOf(context) : null;
      final previewUri = resolveMediaUri(
        asset: asset,
        id: id,
        serverUri: session?.serverUri,
        endpoint: 'preview',
      );
      final thumbUri = resolveMediaUri(
        asset: asset,
        id: id,
        serverUri: session?.serverUri,
        endpoint: 'thumb',
      );

      if (previewUri != null || thumbUri != null) {
        _downloadAndCache(previewCache, thumbCache, previewUri: previewUri, thumbUri: thumbUri);
      }
    } catch (_) {}
  }

  Future<void> _downloadAndCache(
    File previewCache,
    File thumbCache, {
    Uri? previewUri,
    Uri? thumbUri,
  }) async {
    final id = widget.item.id;
    if (_inFlightDownloads.contains(id)) return;
    _inFlightDownloads.add(id);

    if (mounted && _resolvedPath == null && _fallbackThumbPath == null) {
      setState(() => _isLoading = true);
    }

    try {
      final token = mounted ? FrontendSessionScope.maybeOf(context)?.authToken : null;
      final client = createHomeSpaceHttpClient();
      try {
        // Try preview first
        if (previewUri != null) {
          final req = http.Request('GET', previewUri);
          if (token != null) req.headers['Authorization'] = 'Bearer $token';
          final streamed = await client.send(req);

          if (streamed.statusCode == 200) {
            final tempPart = File('${previewCache.path}.part');
            final sink = tempPart.openWrite();
            await streamed.stream.pipe(sink);
            await sink.flush();
            await sink.close();
            if (await tempPart.exists() && await tempPart.length() > 0) {
              await tempPart.rename(previewCache.path);
              _diskPreviewCache[id] = previewCache.path;
              if (mounted) {
                setState(() {
                  _resolvedPath = previewCache.path;
                  _isLoading = false;
                  _hasError = false;
                });
                return;
              }
            }
          }
        }

        // If preview returns 404/failure, fallback to thumbUri
        if (thumbUri != null) {
          final fallbackReq = http.Request('GET', thumbUri);
          if (token != null) fallbackReq.headers['Authorization'] = 'Bearer $token';
          final fallbackStreamed = await client.send(fallbackReq);
          if (fallbackStreamed.statusCode == 200) {
            final tempPart = File('${thumbCache.path}.part');
            final sink = tempPart.openWrite();
            await fallbackStreamed.stream.pipe(sink);
            await sink.flush();
            await sink.close();
            if (await tempPart.exists() && await tempPart.length() > 0) {
              await tempPart.rename(thumbCache.path);
              if (mounted) {
                setState(() {
                  _fallbackThumbPath = thumbCache.path;
                  _isLoading = false;
                  _hasError = false;
                });
                return;
              }
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {} finally {
      _inFlightDownloads.remove(id);
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (_resolvedPath == null && _fallbackThumbPath == null) {
          _hasError = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item.title;

    // 1. Fully resolved image (local file on device or cached preview on disk)
    if (_resolvedPath != null) {
      if (_resolvedPath!.startsWith('assets/')) {
        return Image.asset(
          _resolvedPath!,
          fit: BoxFit.contain,
          semanticLabel: title,
          errorBuilder: (_, _, _) => _buildErrorFallback(),
        );
      }
      if (File(_resolvedPath!).existsSync()) {
        return Image.file(
          File(_resolvedPath!),
          fit: BoxFit.contain,
          semanticLabel: title,
          errorBuilder: (_, _, _) => _buildErrorFallback(),
        );
      } else {
        // Local file was removed/deleted from device; clear stale cache and re-resolve
        _resolvedPath = null;
        _localPathCache.remove(widget.item.title.trim());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resolvePhoto();
        });
      }
    }

    // 2. Base layer: cached thumbnail if preview is still downloading
    if (_fallbackThumbPath != null) {
      if (File(_fallbackThumbPath!).existsSync()) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(_fallbackThumbPath!),
              fit: BoxFit.contain,
              semanticLabel: title,
            ),
            if (_isLoading)
              Positioned(
                bottom: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        );
      } else {
        _fallbackThumbPath = null;
      }
    }

    // 3. Fallback network image if on web or if paths not yet loaded
    final session = FrontendSessionScope.maybeOf(context);
    final targetUri = resolveMediaUri(
      asset: widget.item.asset,
      id: widget.item.id,
      serverUri: session?.serverUri,
      endpoint: 'preview',
    ) ?? resolveMediaUri(
      asset: widget.item.asset,
      id: widget.item.id,
      serverUri: session?.serverUri,
      endpoint: 'thumb',
    );

    if (targetUri != null) {
      final token = session?.authToken;
      final authHeaders = token != null ? {'Authorization': 'Bearer $token'} : null;
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            targetUri.toString(),
            headers: authHeaders,
            fit: BoxFit.contain,
            semanticLabel: title,
            errorBuilder: (_, _, _) => _buildErrorFallback(),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  color: const Color(0xFFF39C12),
                ),
              );
            },
          ),
        ],
      );
    }

    if (_hasError) {
      return _buildErrorFallback();
    }

    // 4. Loading state with subtle animation
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFF39C12),
        ),
      );
    }

    // 5. Error state with retry action
    return _buildErrorFallback();
  }

  Widget _buildErrorFallback() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x33F39C12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.broken_image_rounded,
              color: Color(0xFFF39C12),
              size: 48,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Couldn’t load this photo',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _hasError = false;
                _isLoading = true;
              });
              _resolvePhoto();
            },
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            label: const Text(
              'Retry',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0x33FFFFFF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerView extends StatefulWidget {
  final MediaItem item;
  final bool active;
  const _VideoPlayerView({
    super.key,
    required this.item,
    this.active = true,
  });

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  String? _posterPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initPlayer();
    });
  }

  @override
  void didUpdateWidget(covariant _VideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      _controller?.pause();
    }
  }

  Future<void> _initPlayer() async {
    final asset = widget.item.asset;
    final token = FrontendSessionScope.maybeOf(context)?.authToken;
    final authHeaders = token != null ? {'Authorization': 'Bearer $token'} : null;

    try {
      File? localFile;
      if (!kIsWeb) {
        if (File(asset).existsSync() && File(asset).lengthSync() > 0) {
          localFile = File(asset);
        } else {
          // 1. Search device storage via native MediaStore for instant 0ms playback
          final title = widget.item.title.trim();
          if (title.isNotEmpty) {
            final found = await DeviceMediaService.findLocalMedia(title, isVideo: true);
            if (found != null && File(found).existsSync() && File(found).lengthSync() > 0) {
              localFile = File(found);
            }
          }

          // 2. Check if video was previously cached in temp directory
          if (localFile == null) {
            try {
              final tempDir = await getTemporaryDirectory();
              final cached = File('${tempDir.path}/video_${widget.item.id}.mp4');
              if (cached.existsSync() && cached.lengthSync() > 0) {
                localFile = cached;
              }
            } catch (_) {}
          }

          // 3. Check fallback common directories
          if (localFile == null && title.isNotEmpty) {
            final candidateDirs = [
              '/storage/emulated/0/DCIM/Camera',
              '/storage/emulated/0/DCIM',
              '/storage/emulated/0/Pictures',
              '/storage/emulated/0/Pictures/Screenshots',
              '/storage/emulated/0/Pictures/HomeSpace',
              '/storage/emulated/0/Movies',
              '/storage/emulated/0/Movies/HomeSpace',
              '/storage/emulated/0/Download',
              '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',
              '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images',
            ];
            for (final dir in candidateDirs) {
              final f = File('$dir/$title');
              if (f.existsSync() && f.lengthSync() > 0) {
                localFile = f;
                break;
              }
            }
          }
        }
      }

      final session = mounted ? FrontendSessionScope.maybeOf(context) : null;
      final videoUri = resolveMediaUri(
        asset: asset,
        id: widget.item.id,
        serverUri: session?.serverUri,
        endpoint: 'file',
      );

      if (localFile != null) {
        DeviceMediaService.getVideoThumbnail(
          localFile.path,
          fileName: widget.item.title.trim(),
        ).then((thumb) {
          if (mounted && thumb != null) {
            setState(() => _posterPath = thumb);
          }
        });
        _controller = VideoPlayerController.file(localFile);
      } else if (videoUri != null) {
        var playUri = videoUri;
        if (token != null && !playUri.queryParameters.containsKey('token')) {
          final query = Map<String, String>.from(playUri.queryParameters);
          query['token'] = token;
          playUri = playUri.replace(queryParameters: query);
        }
        _controller = VideoPlayerController.networkUrl(
          playUri,
          httpHeaders: authHeaders ?? const {},
        );
      } else {
        _controller = VideoPlayerController.asset(asset);
      }

      await _controller!.initialize();
      if (!mounted) {
        _controller?.dispose();
        return;
      }
      setState(() {
        _initialized = true;
      });
      _controller!.addListener(_onControllerUpdate);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_initialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _showControls = true;
      } else {
        _controller!.play();
        _showControls = false;
      }
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.amber, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Could not play video',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _initialized = false;
                  });
                  _initPlayer();
                },
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (!_initialized || _controller == null) {
      final token = FrontendSessionScope.maybeOf(context)?.authToken;
      final authHeaders = token != null ? {'Authorization': 'Bearer $token'} : null;
      return Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: _posterPath != null && File(_posterPath!).existsSync()
                ? Image.file(File(_posterPath!), fit: BoxFit.contain)
                : () {
                    final session = FrontendSessionScope.maybeOf(context);
                    final posterUri = resolveMediaUri(
                      asset: widget.item.asset,
                      id: widget.item.id,
                      serverUri: session?.serverUri,
                      endpoint: 'thumb',
                    );
                    if (posterUri != null) {
                      return Image.network(
                        posterUri.toString(),
                        fit: BoxFit.contain,
                        headers: authHeaders,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      );
                    }
                    return const SizedBox.shrink();
                  }(),
          ),
          Container(color: Colors.black45),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text(
                  'Loading video…',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final isPlaying = _controller!.value.isPlaying;
    final isBuffering = _controller!.value.isBuffering;
    final position = _controller!.value.position;
    final duration = _controller!.value.duration;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _showControls = !_showControls;
        });
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
          if (isBuffering)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Buffering…',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          if (_showControls || !isPlaying)
            Container(
              decoration: const BoxDecoration(
                color: Colors.black26,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 64,
                color: Colors.white,
                icon: Icon(
                  isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                ),
                onPressed: _togglePlayPause,
              ),
            ),
          if (_showControls || !isPlaying)
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VideoProgressIndicator(
                      _controller!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFF1677E8),
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
