import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/album_widgets.dart';
import '../design/cartoon_artwork.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import 'library_widgets.dart';
import 'album_editor_page.dart';
import 'album_members_page.dart';
import 'media_viewer.dart';

class AlbumPage extends StatefulWidget {
  final String albumId;
  const AlbumPage({super.key, required this.albumId});
  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  bool selecting = false;
  final selected = <String>{};
  void clear() => setState(() {
    selecting = false;
    selected.clear();
  });
  void toggle(String id) => setState(() {
    selecting = true;
    selected.contains(id) ? selected.remove(id) : selected.add(id);
  });
  @override
  Widget build(BuildContext context) =>
      AlbumTheme(child: Builder(builder: _page));

  Widget _page(BuildContext context) {
    final repository = HomeScope.of(context);
    final album = repository.albums
        .where((item) => item.id == widget.albumId)
        .firstOrNull;
    if (album == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Collection')),
        body: const SingleChildScrollView(
          child: SpaceEmpty(
            icon: Icons.photo_album_outlined,
            title: 'This album is unavailable',
            message: 'Return to Collections and try again.',
          ),
        ),
      );
    }
    final photos = repository.photosFor(album).toList()
      ..sort((a, b) {
        final result = b.takenAt.compareTo(a.takenAt);
        return result == 0 ? a.id.compareTo(b.id) : result;
      });
    final ids = selected
        .where((id) => photos.any((item) => item.id == id))
        .toList();
    final role = album.roleFor(repository.profile.userId);
    final owner = role == AlbumRole.owner;
    final canAdd = owner || role == AlbumRole.contributor;
    final busy = repository.pendingWrites > 0;
    final canRemove =
        ids.isNotEmpty &&
        !busy &&
        (owner ||
            role == AlbumRole.contributor &&
                ids.every(
                  (id) => album.addedBy[id] == repository.profile.userId,
                ));
    final text = Theme.of(context).textTheme;
    final style = SpaceStyle.of(context);
    final cover = repository.coverFor(album);
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) clear();
      },
      child: Scaffold(
        appBar: AppBar(
          title: selecting ? Text('${ids.length} selected') : null,
          leading: selecting
              ? IconButton(
                  tooltip: 'Cancel selection',
                  onPressed: clear,
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
          actions: selecting
              ? [
                  IconButton(
                    tooltip: 'Select all album photos',
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: () => setState(
                      () => selected.addAll(photos.map((photo) => photo.id)),
                    ),
                  ),
                ]
              : [
                  if (canAdd && photos.isNotEmpty)
                    IconButton(
                      tooltip: 'Select album photos',
                      icon: const Icon(Icons.checklist_rounded),
                      onPressed: () => setState(() => selecting = true),
                    ),
                  if (owner)
                    PopupMenuButton<String>(
                      tooltip: 'Album options',
                      enabled: !busy,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit album')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete album'),
                        ),
                      ],
                      onSelected: (action) async {
                        if (action == 'edit') {
                          await openAlbumEditor(context, album: album);
                        } else {
                          final confirmed = await confirmLibraryAction(
                            context,
                            title: 'Delete this album?',
                            message:
                                '“${album.title}” will be removed. Its photos stay in your library and other albums.',
                            confirm: 'Delete album',
                            destructive: true,
                          );
                          if (!confirmed || !context.mounted) return;
                          final saved = await saveLocalChange(
                            context,
                            () => repository.deleteAlbum(album.id),
                          );
                          if (saved && context.mounted) Navigator.pop(context);
                        }
                      },
                    ),
                ],
          bottom: !selecting
              ? null
              : SelectionActions(
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('remove-album-photos'),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      label: const Text('Remove from album'),
                      onPressed: !canRemove
                          ? null
                          : () async {
                              final confirmed = await confirmLibraryAction(
                                context,
                                title:
                                    'Remove ${ids.length} ${ids.length == 1 ? 'memory' : 'memories'}?',
                                message: 'They stay in your library and any other albums.',
                                confirm: 'Remove',
                              );
                              if (!confirmed || !context.mounted) return;
                              final saved = await saveLocalChange(
                                context,
                                () => repository.removeManyFromAlbum(
                                  album.id,
                                  ids,
                                ),
                              );
                              if (saved && mounted) clear();
                            },
                    ),
                    if (owner)
                      OutlinedButton.icon(
                        key: const ValueKey('set-album-cover'),
                        icon: const Icon(Icons.photo_outlined),
                        label: const Text('Set as cover'),
                        onPressed: ids.length != 1 || busy
                            ? null
                            : () async {
                                final saved = await saveLocalChange(
                                  context,
                                  () => repository.setAlbumCover(
                                    album.id,
                                    ids.single,
                                  ),
                                );
                                if (saved && mounted) clear();
                              },
                      ),
                  ],
                ),
        ),
        body: CustomScrollView(
          key: ValueKey('album-scroll-${album.id}'),
          slivers: [
            if (!selecting)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          height: 152,
                          width: double.infinity,
                          child: cover == null
                              ? ColoredBox(
                                  color: style.accentSoft,
                                  child: const Center(child: AlbumSticker()),
                                )
                              : MediaThumbnail(media: cover),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(album.title, style: text.headlineMedium),
                      const SizedBox(height: 5),
                      Text(
                        '${photos.length} ${photos.length == 1 ? 'memory' : 'memories'} · ${album.shared ? 'Shared album' : 'Personal album'}',
                        key: const ValueKey('album-summary'),
                        style: text.bodyMedium,
                      ),
                      if (album.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(album.description, style: text.bodyMedium),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: AlbumPeople(
                              members: [
                                for (final member in album.memberships)
                                  repository.memberById(member.userId),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            key: const ValueKey('album-members'),
                            icon: const Icon(
                              Icons.people_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('Members'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              side: BorderSide(color: style.border),
                            ),
                            onPressed: () => openSpacePage<void>(
                              context,
                              AlbumMembersPage(albumId: album.id),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (canAdd) ...[
                        SpaceButton(
                          key: const ValueKey('add-album-photos'),
                          label: 'Add photos',
                          icon: Icons.add_photo_alternate_outlined,
                          onPressed: busy
                              ? null
                              : () => openSpacePage<void>(
                                  context,
                                  AlbumMediaPicker(albumId: album.id),
                                ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(switch (role) {
                        AlbumRole.owner => 'Owner · You manage this album.',
                        AlbumRole.contributor => 'Contributor · Add memories and remove your own additions.',
                        _ => 'Viewer · Enjoy the memories in this album.',
                      }, style: text.bodyMedium!.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            if (photos.isEmpty)
              const SliverToBoxAdapter(
                child: SpaceEmpty(
                  icon: Icons.photo_album_outlined,
                  title: 'Room for new memories',
                  message: 'Add a few favorites from your library.',
                ),
              ),
            for (final group in photos.map(repository.groupFor).toSet()) ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: SpaceSection(
                    group,
                    detail: albumMemoryCount(
                      photos
                          .where((photo) => repository.groupFor(photo) == group)
                          .length,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: libraryColumns(context),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: photos
                      .where((photo) => repository.groupFor(photo) == group)
                      .length,
                  itemBuilder: (context, index) {
                    final photo = photos
                        .where((photo) => repository.groupFor(photo) == group)
                        .elementAt(index);
                    return MemoryTile(
                      key: ValueKey('album-memory-${photo.id}'),
                      media: photo,
                      selected: selecting ? selected.contains(photo.id) : null,
                      subtitle: album.shared
                          ? repository.memberById(album.addedBy[photo.id]!).name
                          : null,
                      avatarAttribution: true,
                      onLongPress: canAdd ? () => toggle(photo.id) : null,
                      onTap: selecting
                          ? () => toggle(photo.id)
                          : () => openMediaViewer(
                              context,
                              mediaIds: photos
                                  .map((photo) => photo.id)
                                  .toList(),
                              initialId: photo.id,
                            ),
                    );
                  },
                ),
              ),
            ],
            const SliverToBoxAdapter(
              child: SafeArea(top: false, child: SizedBox(height: 8)),
            ),
          ],
        ),
      ),
    );
  }
}

class AlbumMediaPicker extends StatefulWidget {
  final String albumId;
  const AlbumMediaPicker({super.key, required this.albumId});
  @override
  State<AlbumMediaPicker> createState() => _AlbumMediaPickerState();
}

class _AlbumMediaPickerState extends State<AlbumMediaPicker> {
  final selected = <String>{};
  final search = TextEditingController();
  String filter = 'All';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AlbumTheme(child: Builder(builder: _page));

  Widget _page(BuildContext context) {
    final repository = HomeScope.of(context);
    final album = repository.albums
        .where((item) => item.id == widget.albumId)
        .firstOrNull;
    final available = repository.media
        .where((item) => album != null && !album.mediaIds.contains(item.id))
        .toList();
    final photos = available
        .where(
          (item) =>
              (filter == 'All' ||
                  (filter == 'Favorites'
                      ? repository.favorites.contains(item.id)
                      : item.kind == MediaKind.video)) &&
              (item.title.toLowerCase().contains(
                    search.text.trim().toLowerCase(),
                  ) ||
                  item.category.toLowerCase().contains(
                    search.text.trim().toLowerCase(),
                  )),
        )
        .toList();
    final canAdd =
        album != null &&
        [
          AlbumRole.owner,
          AlbumRole.contributor,
        ].contains(album.roleFor(repository.profile.userId));
    final ids = selected
        .where((id) => available.any((item) => item.id == id))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add photos',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        actions: MediaQuery.textScalerOf(context).scale(14) > 19
            ? null
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Center(
                    child: Text(
                      '${ids.length} selected',
                      style: Theme.of(context).textTheme.labelMedium!
                          .copyWith(color: SpaceStyle.of(context).accentInk),
                    ),
                  ),
                ),
              ],
      ),
      body: CustomScrollView(
        key: const ValueKey('album-picker-scroll'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const ValueKey('album-photo-search'),
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search photos',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final option in ['All', 'Favorites', 'Videos'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SpaceFilter(
                              label: option,
                              selected: filter == option,
                              onTap: () => setState(() => filter = option),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${ids.length} selected · ${photos.length} available',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (!canAdd) ...[
                    const SizedBox(height: 8),
                    Text(
                      album == null ? 'This album is unavailable.' : 'You can view this album. An owner can change your role.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (photos.isEmpty)
            SliverToBoxAdapter(
              child: SpaceEmpty(
                icon: Icons.photo_library_outlined,
                title: available.isEmpty
                    ? 'All together already'
                    : 'No matching memories',
                message: available.isEmpty
                    ? 'Every available memory is already in this album.'
                    : 'Try a different search.',
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: libraryColumns(context),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: photos.length,
              itemBuilder: (context, index) {
                final photo = photos[index];
                return MemoryTile(
                  key: ValueKey('pick-${photo.id}'),
                  media: photo,
                  selected: selected.contains(photo.id),
                  onTap: () => setState(() {
                    selected.contains(photo.id)
                        ? selected.remove(photo.id)
                        : selected.add(photo.id);
                  }),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
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
            key: const ValueKey('save-album-photos'),
            label: 'Add ${ids.length} ${ids.length == 1 ? 'photo' : 'photos'}',
            icon: Icons.add_rounded,
            onPressed: !canAdd || ids.isEmpty || repository.pendingWrites > 0
                ? null
                : () async {
                    final saved = await saveLocalChange(
                      context,
                      () => repository.addManyToAlbum(widget.albumId, ids),
                    );
                    if (saved && context.mounted) Navigator.pop(context);
                  },
          ),
        ),
      ),
    );
  }
}
