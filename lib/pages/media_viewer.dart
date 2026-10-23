import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../design/photo_action.dart';
import '../domain/models.dart';
import 'library_widgets.dart';
import 'local_edit_sheets.dart';

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
  final zoomKeys = <String, GlobalKey<_ZoomablePhotoState>>{};
  bool chrome = true;
  bool zoomed = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void changePage(int next) {
    zoomKeys[widget.mediaIds[index]]?.currentState?.reset();
    setState(() {
      index = next;
      zoomed = false;
    });
  }

  void step(int amount) {
    final duration = spaceMotion(context, 220);
    if (duration == Duration.zero) {
      controller.jumpToPage(index + amount);
    } else {
      controller.animateToPage(
        index + amount,
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
                  final compact = constraints.maxHeight < 450;
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  final top = compact
                      ? 80.0
                      : 88 + 48 * (scale.clamp(1.0, 2.0).toDouble() - 1);
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
                          child: widget.mediaIds.isEmpty
                              ? const Center(
                                  child: Text('This memory is unavailable'),
                                )
                              : PageView.builder(
                                  key: const ValueKey('viewer-pages'),
                                  controller: controller,
                                  physics: zoomed
                                      ? const NeverScrollableScrollPhysics()
                                      : const PageScrollPhysics(),
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
                                    return _ZoomablePhoto(
                                      key: zoomKeys.putIfAbsent(
                                        item.id,
                                        () => GlobalKey<_ZoomablePhotoState>(),
                                      ),
                                      media: item,
                                      onTap: () =>
                                          setState(() => chrome = !chrome),
                                      onZoom: (value) {
                                        if (mounted &&
                                            page == index &&
                                            zoomed != value) {
                                          setState(() => zoomed = value);
                                        }
                                      },
                                    );
                                  },
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
                                  IconButton(
                                    tooltip: 'Previous photo',
                                    onPressed: index > 0
                                        ? () => step(-1)
                                        : null,
                                    icon: const Icon(
                                      Icons.chevron_left_rounded,
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (photo != null)
                                          Text(
                                            _dateLabel(photo.takenAt),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: text.labelLarge,
                                          ),
                                        if (photo != null && !compact)
                                          Text(
                                            photo.title,
                                            key: const ValueKey('viewer-title'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: text.bodyMedium!.copyWith(
                                              fontSize: 12,
                                              color: const Color(0xFFDCE3ED),
                                            ),
                                          ),
                                        Semantics(
                                          liveRegion: true,
                                          label:
                                              '${widget.mediaIds.isEmpty ? 0 : index + 1} of ${widget.mediaIds.length} memories',
                                          child: ExcludeSemantics(
                                            child: Text(
                                              '${widget.mediaIds.isEmpty ? 0 : index + 1} / ${widget.mediaIds.length}',
                                              key: const ValueKey(
                                                'viewer-position',
                                              ),
                                              style: text.bodyMedium!.copyWith(
                                                fontSize: 11,
                                                color: const Color(0xFFDCE3ED),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Next photo',
                                    onPressed:
                                        index < widget.mediaIds.length - 1
                                        ? () => step(1)
                                        : null,
                                    icon: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: zoomed ? 'Reset zoom' : 'Zoom in',
                                    onPressed:
                                        !available ||
                                            photo.kind != MediaKind.photo
                                        ? null
                                        : () => zoomKeys[photo.id]?.currentState
                                              ?.toggle(),
                                    icon: Icon(
                                      zoomed
                                          ? Icons.zoom_out_rounded
                                          : Icons.zoom_in_rounded,
                                    ),
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
                                                    Navigator.pop(context);
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
                                                    Navigator.pop(context);
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
                                                    Navigator.pop(context);
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
                  Text(photo.title, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date & time',
                    value:
                        '${_dateLabel(date)} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                  ),
                  _DetailRow(
                    icon: Icons.insert_drive_file_outlined,
                    label: 'Filename',
                    value: photo.asset.split('/').last,
                    note:
                        '${photo.category} · Bundled sample · Available offline',
                  ),
                  const SizedBox(height: 8),
                  Text('Albums', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (albums.isEmpty)
                    const _DetailRow(
                      icon: Icons.photo_album_outlined,
                      label: 'In your library',
                      value: 'This memory has a home in your library.',
                    )
                  else
                    for (final album in albums)
                      _DetailRow(
                        icon: Icons.photo_album_outlined,
                        label: album.title,
                        value:
                            'Added by ${repository.memberById(album.addedBy[photo.id]!).name}',
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
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
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

class _ZoomablePhoto extends StatefulWidget {
  final MediaItem media;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoom;
  const _ZoomablePhoto({
    super.key,
    required this.media,
    required this.onTap,
    required this.onZoom,
  });
  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final transform = TransformationController();
  late final animation = AnimationController(vsync: this)..addListener(_tick);
  Animation<Matrix4>? tween;
  Offset? tapped;
  Size size = Size.zero;
  bool zoomed = false;
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
        label: widget.media.title,
        button: true,
        onTap: widget.onTap,
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: widget.onTap,
            onDoubleTapDown: (details) => tapped = details.localPosition,
            onDoubleTap: () => toggle(at: tapped),
            child: InteractiveViewer(
              transformationController: transform,
              minScale: 1,
              maxScale: 4,
              panEnabled: zoomed,
              onInteractionStart: (_) => animation.stop(),
              child: SizedBox.expand(
                child: Image.asset(
                  widget.media.asset,
                  fit: BoxFit.contain,
                  semanticLabel: widget.media.title,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Text('Couldn’t open this photo')),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
