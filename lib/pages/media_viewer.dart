import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../design/photo_action.dart';
import '../design/album_widgets.dart';
import 'album_page.dart';
import '../domain/models.dart';
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

Future<BundledPhotoMetadata> readBundledPhotoMetadata(String asset) async {
  final data = await rootBundle.load(asset);
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      return BundledPhotoMetadata(
        data.lengthInBytes,
        descriptor.width,
        descriptor.height,
      );
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
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
  bool chrome = true;
  bool zoomed = false;
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
            value: SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: const Color(0xFF101519),
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarContrastEnforced: false,
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
                        child: AnimatedPadding(
                          duration: spaceMotion(context, 160),
                          padding: EdgeInsets.only(
                            top: chrome
                                ? top + MediaQuery.paddingOf(context).top
                                : 0,
                            bottom: chrome
                                ? bottom + MediaQuery.paddingOf(context).bottom
                                : 0,
                          ),
                          child: _PhotoViewport(
                            key: viewportKey,
                            label: photo?.title ?? 'Unavailable memory',
                            canZoom: available && photo.kind == MediaKind.photo,
                            onPageDragStart: startPageDrag,
                            onPageDragUpdate: updatePageDrag,
                            onPageDragEnd: endPageDrag,
                            onPageDragCancel: cancelPageDrag,
                            onTap: () => setState(() => chrome = !chrome),
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
                                        return const SingleChildScrollView(
                                          child: SpaceEmpty(
                                            icon: Icons.movie_outlined,
                                            title: 'Video preview',
                                            message: 'Video playback will be added with the upload experience.',
                                          ),
                                        );
                                      }
                                      return Image.asset(
                                        item.asset,
                                        fit: BoxFit.contain,
                                        semanticLabel: item.title,
                                        errorBuilder: (_, _, _) => const Center(
                                          child: Text(
                                            'Couldn’t open this photo',
                                          ),
                                        ),
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
                        child: _chrome(
                          context,
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
                          child: _chrome(
                            context,
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
                      if (!chrome)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: SafeArea(
                            child: IconButton(
                              tooltip: 'Show controls',
                              icon: const Icon(Icons.more_horiz_rounded),
                              onPressed: () => setState(() => chrome = true),
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

  Widget _chrome(BuildContext context, Widget child) => IgnorePointer(
    ignoring: !chrome,
    child: AnimatedOpacity(
      opacity: chrome ? 1 : 0,
      duration: spaceMotion(context, 160),
      child: ColoredBox(color: const Color(0xF5101519), child: child),
    ),
  );

  void _showDetails(BuildContext context, MediaItem photo) {
    final repository = HomeScope.of(context);
    final date = photo.takenAt.toLocal();
    final albums = repository.albums.where(
      (album) => album.mediaIds.contains(photo.id),
    );
    final metadata = readBundledPhotoMetadata(photo.asset);
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
                      note: result.hasData
                          ? '${result.data!.fileSize} · ${result.data!.width} × ${result.data!.height}'
                          : result.hasError
                          ? 'File details unavailable'
                          : 'Reading file details…',
                    ),
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
    );
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
  final VoidCallback onTap;
  final ValueChanged<bool> onZoom;
  final GestureDragStartCallback onPageDragStart;
  final GestureDragUpdateCallback onPageDragUpdate;
  final GestureDragEndCallback onPageDragEnd;
  final GestureDragCancelCallback onPageDragCancel;
  const _PhotoViewport({
    super.key,
    required this.child,
    required this.label,
    required this.canZoom,
    required this.onTap,
    required this.onZoom,
    required this.onPageDragStart,
    required this.onPageDragUpdate,
    required this.onPageDragEnd,
    required this.onPageDragCancel,
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
        button: true,
        onTap: widget.onTap,
        child: ExcludeSemantics(
          child: Listener(
            onPointerDown: pointerDown,
            onPointerUp: (event) => pointers.remove(event.pointer),
            onPointerCancel: (event) {
              pointers.remove(event.pointer);
              cancelPaging();
            },
            child: GestureDetector(
              onTap: widget.onTap,
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
