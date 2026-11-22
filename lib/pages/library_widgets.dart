import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../application/device_media_service.dart';
import '../application/frontend_session.dart';
import '../application/home_scope.dart';
import '../data/homespace_api_client.dart';
import '../design/album_widgets.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../design/system_ui.dart';
import '../design/vector_artwork.dart';
import '../domain/models.dart';

Future<T?> openSpacePage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (_, _, _) => Builder(
          builder: (context) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: spaceSystemUiStyle(context),
              child: page,
            );
          },
        ),
        transitionDuration: spaceMotion(context, 240),
        reverseTransitionDuration: spaceMotion(context, 200),
        transitionsBuilder: (_, animation, _, child) {
          final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
          return FadeTransition(
            opacity: eased,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, .035),
                end: Offset.zero,
              ).animate(eased),
              child: child,
            ),
          );
        },
      ),
    );

int libraryColumns(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 340 || MediaQuery.textScalerOf(context).scale(16) > 25) return 2;
  return width > 650 ? 5 : 3;
}

class MediaThumbnail extends StatelessWidget {
  final MediaItem media;
  const MediaThumbnail({super.key, required this.media});

  static void clearLocalCaches() {
    _PhotoThumbnailTileState.clearLocalPathCache();
    _VideoThumbnailTileState.clearLocalCache();
  }

  @override
  Widget build(BuildContext context) {
    if (media.kind == MediaKind.video) {
      return _VideoThumbnailTile(media: media);
    }
    return _PhotoThumbnailTile(media: media);
  }
}

class _PhotoThumbnailTile extends StatefulWidget {
  final MediaItem media;
  const _PhotoThumbnailTile({required this.media});

  @override
  State<_PhotoThumbnailTile> createState() => _PhotoThumbnailTileState();
}

class _PhotoThumbnailTileState extends State<_PhotoThumbnailTile> {
  static final Map<String, String?> _localPathCache = {};
  static final Map<String, String?> _diskThumbCache = {};
  static final Set<String> _inFlightDownloads = {};

  static void clearLocalPathCache() {
    _localPathCache.clear();
  }

  String? _resolvedPath;
  bool _hasError = false;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _resolveThumbnail();
  }

  @override
  void didUpdateWidget(covariant _PhotoThumbnailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id ||
        oldWidget.media.asset != widget.media.asset) {
      _retryCount = 0;
      _hasError = false;
      _resolvedPath = null;
      _resolveThumbnail();
    }
  }

  Future<void> _resolveThumbnail() async {
    final asset = widget.media.asset;
    final title = widget.media.title.trim();
    final id = widget.media.id;

    // 1. Direct local file on disk
    if (!kIsWeb && !asset.startsWith('http://') && !asset.startsWith('https://')) {
      if (File(asset).existsSync()) {
        if (mounted) setState(() => _resolvedPath = asset);
        return;
      }
    }

    if (kIsWeb) return;

    // 2. Check local device storage via MediaStore / candidate folders (0ms instant render)
    if (title.isNotEmpty) {
      if (_localPathCache.containsKey(title)) {
        final cached = _localPathCache[title];
        if (cached != null && File(cached).existsSync()) {
          if (mounted) setState(() => _resolvedPath = cached);
          return;
        } else {
          _localPathCache.remove(title);
        }
      }
      final local = await DeviceMediaService.findLocalMedia(title, isVideo: false);
      if (local != null && File(local).existsSync()) {
        _localPathCache[title] = local;
        if (mounted) setState(() => _resolvedPath = local);
        return;
      } else {
        _localPathCache.remove(title);
      }
    }

    // 3. Check persistent disk cache (survives app restarts & memory eviction)
    if (_diskThumbCache.containsKey(id)) {
      final cached = _diskThumbCache[id];
      if (cached != null && File(cached).existsSync() && File(cached).lengthSync() > 0) {
        if (mounted) setState(() => _resolvedPath = cached);
        return;
      } else {
        _diskThumbCache.remove(id);
      }
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final cacheFile = File('${tempDir.path}/thumb_$id.webp');
      if (cacheFile.existsSync() && cacheFile.lengthSync() > 0) {
        _diskThumbCache[id] = cacheFile.path;
        if (mounted) setState(() => _resolvedPath = cacheFile.path);
        return;
      }

      // 4. Download from network & cache to disk with auto-retry
      final session = mounted ? FrontendSessionScope.maybeOf(context) : null;
      final targetUri = resolveMediaUri(
        asset: asset,
        id: id,
        serverUri: session?.serverUri,
        endpoint: 'thumb',
      );
      if (targetUri != null) {
        _downloadAndCache(cacheFile, targetUri);
      }
    } catch (_) {}
  }

  Future<void> _downloadAndCache(File cacheFile, Uri targetUri) async {
    final id = widget.media.id;
    if (_inFlightDownloads.contains(id)) return;
    _inFlightDownloads.add(id);

    try {
      final token = mounted ? FrontendSessionScope.maybeOf(context)?.authToken : null;
      final client = createHomeSpaceHttpClient();
      try {
        final req = http.Request('GET', targetUri);
        if (token != null) req.headers['Authorization'] = 'Bearer $token';
        final streamed = await client.send(req);
        if (streamed.statusCode == 200) {
          final tempPart = File('${cacheFile.path}.part');
          final sink = tempPart.openWrite();
          await streamed.stream.pipe(sink);
          await sink.flush();
          await sink.close();
          if (await tempPart.exists() && await tempPart.length() > 0) {
            await tempPart.rename(cacheFile.path);
            _diskThumbCache[id] = cacheFile.path;
            if (mounted) {
              setState(() {
                _resolvedPath = cacheFile.path;
                _hasError = false;
              });
            }
          }
        } else {
          _handleDownloadFailure();
        }
      } finally {
        client.close();
      }
    } catch (_) {
      _handleDownloadFailure();
    } finally {
      _inFlightDownloads.remove(id);
    }
  }

  void _handleDownloadFailure() {
    if (!mounted) return;
    if (_retryCount < 2) {
      _retryCount++;
      Future.delayed(Duration(milliseconds: 1200 * _retryCount), () {
        if (mounted && _resolvedPath == null) {
          _resolveThumbnail();
        }
      });
    } else {
      setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedPath != null) {
      if (File(_resolvedPath!).existsSync()) {
        return Image.file(
          File(_resolvedPath!),
          fit: BoxFit.cover,
          cacheWidth: 360,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallbackWidget(),
        );
      } else {
        // Local file was removed/deleted; clear stale state and re-resolve from server.
        _resolvedPath = null;
        _localPathCache.remove(widget.media.title.trim());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resolveThumbnail();
        });
      }
    }

    final session = FrontendSessionScope.maybeOf(context);
    final targetUri = resolveMediaUri(
      asset: widget.media.asset,
      id: widget.media.id,
      serverUri: session?.serverUri,
      endpoint: 'thumb',
    );

    if (targetUri != null && !_hasError) {
      final token = session?.authToken;
      return Image.network(
        targetUri.toString(),
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        fit: BoxFit.cover,
        cacheWidth: 360,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return _placeholder();
        },
        errorBuilder: (_, _, _) {
          if (_resolvedPath != null && File(_resolvedPath!).existsSync()) {
            return Image.file(File(_resolvedPath!), fit: BoxFit.cover, cacheWidth: 360);
          }
          return _fallbackWidget();
        },
      );
    }

    if (!kIsWeb && File(widget.media.asset).existsSync()) {
      return Image.file(
        File(widget.media.asset),
        fit: BoxFit.cover,
        cacheWidth: 360,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallbackWidget(),
      );
    }

    if (widget.media.asset.startsWith('assets/')) {
      return Image.asset(
        widget.media.asset,
        fit: BoxFit.cover,
        cacheWidth: 360,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallbackWidget(),
      );
    }

    return _fallbackWidget();
  }

  Widget _placeholder() {
    return Container(
      color: Colors.black12,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black26),
        ),
      ),
    );
  }

  Widget _fallbackWidget() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _hasError = false;
          _retryCount = 0;
        });
        _resolveThumbnail();
      },
      child: Container(
        color: Colors.black12,
        child: const Center(
          child: Icon(Icons.broken_image_outlined, size: 36, color: Colors.black38),
        ),
      ),
    );
  }
}

class _VideoThumbnailTile extends StatefulWidget {
  final MediaItem media;
  const _VideoThumbnailTile({required this.media});

  @override
  State<_VideoThumbnailTile> createState() => _VideoThumbnailTileState();
}

class _VideoThumbnailTileState extends State<_VideoThumbnailTile> {
  static final Set<String> _inFlightVideoDownloads = {};
  static final Map<String, String> _diskVideoThumbCache = {};
  String? _localThumbPath;

  static void clearLocalCache() {
    _diskVideoThumbCache.clear();
  }

  @override
  void initState() {
    super.initState();
    _resolveThumbnail();
  }

  @override
  void didUpdateWidget(covariant _VideoThumbnailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id ||
        oldWidget.media.asset != widget.media.asset) {
      _resolveThumbnail();
    }
  }

  Future<void> _resolveThumbnail() async {
    if (kIsWeb) return;

    final id = widget.media.id;
    if (_diskVideoThumbCache.containsKey(id)) {
      final cached = _diskVideoThumbCache[id]!;
      if (File(cached).existsSync()) {
        if (mounted) setState(() => _localThumbPath = cached);
        return;
      } else {
        _diskVideoThumbCache.remove(id);
      }
    }

    final fileName = widget.media.title.trim();

    // 1. Check persistent disk cache first (fastest, survives deletion of original video)
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheFile = File('${tempDir.path}/thumb_$id.webp');
      if (cacheFile.existsSync() && cacheFile.lengthSync() > 0) {
        _diskVideoThumbCache[id] = cacheFile.path;
        if (mounted) setState(() => _localThumbPath = cacheFile.path);
        return;
      }
    } catch (_) {}

    // 2. Hardware video extraction via MediaStore / local file
    final thumb = await DeviceMediaService.getVideoThumbnail(
      widget.media.asset,
      fileName: fileName.isNotEmpty ? fileName : null,
    );
    if (mounted && thumb != null && File(thumb).existsSync()) {
      _diskVideoThumbCache[id] = thumb;
      try {
        final tempDir = await getTemporaryDirectory();
        final cacheFile = File('${tempDir.path}/thumb_$id.webp');
        if (!cacheFile.existsSync() || cacheFile.lengthSync() == 0) {
          await File(thumb).copy(cacheFile.path);
        }
      } catch (_) {}
      setState(() => _localThumbPath = thumb);
      return;
    }

    // 3. Network download from server
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheFile = File('${tempDir.path}/thumb_$id.webp');
      final session = mounted ? FrontendSessionScope.maybeOf(context) : null;
      final targetUri = resolveMediaUri(
        asset: widget.media.asset,
        id: id,
        serverUri: session?.serverUri,
        endpoint: 'thumb',
      );
      if (targetUri != null && !_inFlightVideoDownloads.contains(id)) {
        _inFlightVideoDownloads.add(id);
        try {
          if (!mounted) return;
          final token = session?.authToken;
          final client = createHomeSpaceHttpClient();
          try {
            final req = http.Request('GET', targetUri);
            if (token != null) req.headers['Authorization'] = 'Bearer $token';
            final streamed = await client.send(req);
            if (streamed.statusCode == 200) {
              final tempPart = File('${cacheFile.path}.part');
              final sink = tempPart.openWrite();
              await streamed.stream.pipe(sink);
              await sink.flush();
              await sink.close();
              if (await tempPart.exists() && await tempPart.length() > 0) {
                await tempPart.rename(cacheFile.path);
                _diskVideoThumbCache[id] = cacheFile.path;
                if (mounted) setState(() => _localThumbPath = cacheFile.path);
              }
            }
          } finally {
            client.close();
          }
        } catch (_) {
        } finally {
          _inFlightVideoDownloads.remove(id);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final session = FrontendSessionScope.maybeOf(context);
    final targetUri = resolveMediaUri(
      asset: widget.media.asset,
      id: widget.media.id,
      serverUri: session?.serverUri,
      endpoint: 'thumb',
    );

    Widget imageWidget;
    if (_localThumbPath != null) {
      if (File(_localThumbPath!).existsSync()) {
        imageWidget = Image.file(
          File(_localThumbPath!),
          fit: BoxFit.cover,
          cacheWidth: 360,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallbackPoster(),
        );
      } else {
        _localThumbPath = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resolveThumbnail();
        });
        imageWidget = _fallbackPoster();
      }
    } else if (targetUri != null) {
      final token = session?.authToken;
      imageWidget = Image.network(
        targetUri.toString(),
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        fit: BoxFit.cover,
        cacheWidth: 360,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return _fallbackPoster();
        },
        errorBuilder: (_, _, _) => _fallbackPoster(),
      );
    } else {
      imageWidget = _fallbackPoster();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        imageWidget,
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 3),
                Text(
                  widget.media.formattedDuration ?? 'Video',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallbackPoster() => Container(
        color: const Color(0xFF1E2A38),
        child: const Center(
          child: Icon(Icons.movie_rounded, color: Colors.white70, size: 36),
        ),
      );
}

class MemoryTile extends StatelessWidget {
  final MediaItem media;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool? selected;
  final bool favorite;
  final String? subtitle;
  final FamilyMember? attribution;
  const MemoryTile({
    super.key,
    required this.media,
    required this.onTap,
    this.onLongPress,
    this.selected,
    this.favorite = false,
    this.subtitle,
    this.attribution,
  });
  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${media.title}${favorite ? ', favorite' : ''}${subtitle == null ? '' : ', $subtitle'}',
      child: RepaintBoundary(
        child: Material(
          color: style.accentSoft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected == true
                  ? const Color(0xFF1677E8)
                  : Colors.transparent,
              width: 3,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaThumbnail(media: media),
                if (selected == null)
                  Positioned(
                    left: 7,
                    top: 7,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0x77000000),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          (media.isSynced || media.asset.startsWith('http'))
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_queue_rounded,
                          color: (media.isSynced || media.asset.startsWith('http'))
                              ? const Color(0xFF8BE84E)
                              : Colors.white70,
                          size: 13,
                        ),
                      ),
                    ),
                  ),
                if (selected != null || favorite)
                  Positioned(
                    right: 7,
                    top: 7,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected == true
                            ? const Color(0xFF1677E8)
                            : const Color(0xAA101519),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          selected == null
                              ? Icons.favorite_rounded
                              : selected!
                              ? Icons.check_rounded
                              : Icons.circle_outlined,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                if (attribution != null)
                  Positioned(
                    right: 7,
                    bottom: 7,
                    child: MemberPortrait(member: attribution!, size: 26),
                  ),
                if (subtitle != null)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xCC101519),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}

class SelectionActions extends StatelessWidget implements PreferredSizeWidget {
  final List<Widget> children;
  const SelectionActions({super.key, required this.children});
  @override
  Size get preferredSize => const Size.fromHeight(68);
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 68,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (final child in children)
            Padding(padding: const EdgeInsets.only(right: 8), child: child),
        ],
      ),
    ),
  );
}

Future<bool> confirmLibraryAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final width = MediaQuery.sizeOf(dialogContext).width;
        final compact =
            width < 360 ||
            (width < 600 &&
                MediaQuery.textScalerOf(dialogContext).scale(14) > 20);
        final cancel = SpaceButton(
          label: 'Cancel',
          backgroundColor: theme.brightness == Brightness.dark
              ? theme.colorScheme.surfaceContainerLow
              : const Color(0xFFEEF1FA),
          foregroundColor: theme.colorScheme.onSurface,
          onPressed: () => Navigator.pop(dialogContext, false),
        );
        final accept = SpaceButton(
          key: const ValueKey('confirm-action'),
          label: confirm,
          backgroundColor: destructive ? const Color(0xFFE12D39) : null,
          foregroundColor: destructive ? Colors.white : null,
          onPressed: () => Navigator.pop(dialogContext, true),
        );
        return AlertDialog(
          scrollable: true,
          backgroundColor: theme.colorScheme.surfaceContainer,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          icon: ExcludeSemantics(
            child: SpaceArtwork(
              'delete-house',
              width: 112,
              height: 76,
              fit: BoxFit.contain,
            ),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          actions: [
            compact
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [cancel, const SizedBox(height: 12), accept],
                  )
                : Row(
                    children: [
                      Expanded(child: cancel),
                      const SizedBox(width: 12),
                      Expanded(child: accept),
                    ],
                  ),
          ],
        );
      },
    ) ??
    false;

Future<bool> trashMemories(BuildContext context, List<String> ids) async {
  final repository = HomeScope.of(context);
  final actionContext = Navigator.of(context).context;
  final confirmed = await confirmLibraryAction(
    context,
    title:
        'Move ${ids.length == 1 ? 'memory' : '${ids.length} memories'} to Trash?',
    message: 'They will disappear from your library and albums. You can restore them from Trash in Profile.',
    confirm: 'Move to Trash',
  );
  if (!confirmed || !context.mounted) return false;
  final saved = await saveLocalChange(
    context,
    () => repository.moveManyToTrash(ids),
  );
  if (saved && context.mounted) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          96 + MediaQuery.paddingOf(context).bottom,
        ),
        content: Text(
          '${ids.length} ${ids.length == 1 ? 'memory' : 'memories'} moved to Trash',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            messenger.clearSnackBars();
            if (actionContext.mounted) {
              saveLocalChange(actionContext, () => repository.restoreMany(ids));
            }
          },
        ),
      ),
    );
  }
  return saved;
}

Future<bool> deleteTrashedMemories(
  BuildContext context,
  List<String> ids,
) async {
  final repository = HomeScope.of(context);
  final confirmed = await confirmLibraryAction(
    context,
    title: 'Delete permanently?',
    message: ids.length == 1
        ? 'This memory cannot be restored.'
        : 'These ${ids.length} memories cannot be restored.',
    confirm: 'Delete',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  final saved = await saveLocalChange(context, () => repository.deleteManyPermanently(ids));
  if (saved && context.mounted) {
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          96 + MediaQuery.paddingOf(context).bottom,
        ),
        content: Text(
          '${ids.length} ${ids.length == 1 ? 'memory' : 'memories'} permanently deleted',
        ),
      ),
    );
  }
  return saved;
}
