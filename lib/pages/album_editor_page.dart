import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/album_widgets.dart';
import '../design/cartoon_artwork.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import 'library_widgets.dart';

Future<String?> openAlbumEditor(
  BuildContext context, {
  Album? album,
  List<String> mediaIds = const [],
}) => openSpacePage<String>(
  context,
  AlbumEditorPage(album: album, mediaIds: mediaIds),
);

class AlbumEditorPage extends StatefulWidget {
  final Album? album;
  final List<String> mediaIds;
  const AlbumEditorPage({super.key, this.album, this.mediaIds = const []});
  @override
  State<AlbumEditorPage> createState() => _AlbumEditorPageState();
}

class _AlbumEditorPageState extends State<AlbumEditorPage> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.album?.title ?? '');
  late final description = TextEditingController(
    text: widget.album?.description ?? '',
  );
  String? coverId;
  bool coverChanged = false;
  bool initialized = false;
  bool busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      final repository = HomeScope.of(context);
      coverId = widget.album == null
          ? widget.mediaIds
                .map(repository.mediaById)
                .whereType<MediaItem>()
                .where((item) => item.kind == MediaKind.photo)
                .firstOrNull
                ?.id
          : repository.coverFor(widget.album!)?.id;
      initialized = true;
    }
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AlbumTheme(child: Builder(builder: _page));

  Widget _page(BuildContext context) {
    final repository = HomeScope.of(context);
    final current = widget.album == null
        ? null
        : repository.albums
              .where((album) => album.id == widget.album!.id)
              .firstOrNull;
    final editable =
        widget.album == null ||
        current?.roleFor(repository.profile.userId) == AlbumRole.owner;
    final candidates =
        (current == null && widget.album == null
                ? repository.media
                : current == null
                ? <MediaItem>[]
                : repository.photosFor(current))
            .where((photo) => photo.kind == MediaKind.photo)
            .toList();
    final cover = candidates.where((photo) => photo.id == coverId).firstOrNull;
    final text = Theme.of(context).textTheme;
    final style = SpaceStyle.of(context);
    final disabled = busy || repository.pendingWrites > 0 || !editable;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album == null ? 'Create album' : 'Edit album'),
        centerTitle: true,
      ),
      body: Form(
        key: form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 172,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (cover != null)
                        MediaThumbnail(media: cover)
                      else
                        ColoredBox(
                          color: style.accentSoft,
                          child: const Center(child: AlbumSticker()),
                        ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: IconButton.filled(
                          key: const ValueKey('choose-album-cover'),
                          tooltip: 'Choose album cover',
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainer,
                            foregroundColor: style.accentInk,
                          ),
                          onPressed: disabled || candidates.isEmpty
                              ? null
                              : () async {
                                  FocusScope.of(context).unfocus();
                                  final chosen = await openSpacePage<String>(
                                    context,
                                    AlbumCoverPicker(
                                      mediaIds: candidates
                                          .map((photo) => photo.id)
                                          .toList(),
                                      initialId: coverId,
                                    ),
                                  );
                                  if (chosen != null && mounted) {
                                    setState(() {
                                      coverId = chosen;
                                      coverChanged = true;
                                    });
                                  }
                                },
                          icon: const Icon(Icons.photo_camera_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.album == null && coverId != null
                    ? 'The cover photo will be included in this album.'
                    : candidates.isEmpty
                    ? 'Add photos later to choose an album cover.'
                    : 'Choose a favorite moment for the cover.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 22),
              Text('Title', style: text.labelLarge),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('album-name'),
                controller: name,
                enabled: !disabled,
                maxLength: 80,
                decoration: const InputDecoration(hintText: 'Family weekends'),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Give your album a name.'
                    : null,
              ),
              const SizedBox(height: 12),
              Text('Description (optional)', style: text.labelLarge),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('album-description'),
                controller: description,
                enabled: !disabled,
                maxLength: 4096,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'The little moments worth keeping.',
                ),
              ),
              if (!editable)
                Text(
                  'Only the album owner can save these changes.',
                  style: text.bodyMedium,
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SpaceButton(
            key: const ValueKey('save-album-editor'),
            label: busy ? 'Saving…' : 'Save album',
            onPressed: disabled
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    FocusScope.of(context).unfocus();
                    setState(() => busy = true);
                    String? savedId;
                    final saved = await saveLocalChange(context, () async {
                      if (widget.album == null) {
                        savedId = await repository.createAlbum(
                          name.text,
                          description: description.text,
                          mediaIds: {...widget.mediaIds, ?coverId}.toList(),
                          coverId: coverId,
                        );
                      } else {
                        await repository.updateAlbum(
                          widget.album!.id,
                          name.text,
                          description.text,
                          coverId: coverChanged ? coverId : null,
                        );
                        savedId = widget.album!.id;
                      }
                    });
                    if (!mounted) return;
                    setState(() => busy = false);
                    if (saved && context.mounted) {
                      Navigator.pop(context, savedId);
                    }
                  },
          ),
        ),
      ),
    );
  }
}

class AlbumCoverPicker extends StatefulWidget {
  final List<String> mediaIds;
  final String? initialId;
  const AlbumCoverPicker({super.key, required this.mediaIds, this.initialId});
  @override
  State<AlbumCoverPicker> createState() => _AlbumCoverPickerState();
}

class _AlbumCoverPickerState extends State<AlbumCoverPicker> {
  late String? selected = widget.initialId;
  @override
  Widget build(BuildContext context) => AlbumTheme(
    child: Builder(
      builder: (context) {
        final repository = HomeScope.of(context);
        final photos = repository.media
            .where(
              (photo) =>
                  widget.mediaIds.contains(photo.id) &&
                  photo.kind == MediaKind.photo,
            )
            .toList();
        final valid = photos.any((photo) => photo.id == selected);
        return Scaffold(
          appBar: AppBar(title: const Text('Choose cover'), centerTitle: true),
          body: GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: libraryColumns(context),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) => MemoryTile(
              key: ValueKey('cover-${photos[index].id}'),
              media: photos[index],
              selected: selected == photos[index].id,
              onTap: () => setState(() => selected = photos[index].id),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SpaceButton(
                key: const ValueKey('use-album-cover'),
                label: 'Use this cover',
                onPressed: !valid
                    ? null
                    : () => Navigator.pop(context, selected),
              ),
            ),
          ),
        );
      },
    ),
  );
}
