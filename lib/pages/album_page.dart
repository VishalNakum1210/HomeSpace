import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import 'library_widgets.dart';
import 'local_edit_sheets.dart';
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
  Widget build(BuildContext context) {
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
    final photos = repository.photosFor(album);
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
          title: Text(selecting ? '${ids.length} selected' : 'Collection'),
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
                          await showSpaceSheet<String>(
                            context,
                            AlbumNameSheet(album: album),
                          );
                        } else {
                          final confirmed = await confirmLibraryAction(
                            context,
                            title: 'Delete this album?',
                            message:
                                '“${album.title}” will be removed. Its photos stay in your library and other albums.',
                            confirm: 'Delete album',
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
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: cover == null
                              ? ColoredBox(
                                  color: style.accentSoft,
                                  child: Icon(
                                    Icons.photo_album_outlined,
                                    color: style.accentInk,
                                    size: 60,
                                  ),
                                )
                              : MediaThumbnail(media: cover),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SpaceBadge(
                            album.shared ? 'SHARED ALBUM' : 'MY ALBUM',
                          ),
                          const SpaceBadge('LOCAL DEMO'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(album.title, style: text.headlineMedium),
                      if (album.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(album.description, style: text.bodyLarge),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        album.shared
                            ? 'A space for ${album.memberships.length} family members'
                            : 'A little collection of your own',
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your role: ${role?.name ?? 'viewer'}',
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (canAdd)
                            OutlinedButton.icon(
                              key: const ValueKey('add-album-photos'),
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: const Text('Add memories'),
                              onPressed: busy
                                  ? null
                                  : () => openSpacePage<void>(
                                      context,
                                      AlbumMediaPicker(albumId: album.id),
                                    ),
                            ),
                          OutlinedButton.icon(
                            key: const ValueKey('album-members'),
                            icon: const Icon(Icons.people_outline_rounded),
                            label: Text(
                              '${album.memberships.length} ${album.memberships.length == 1 ? 'member' : 'members'}',
                            ),
                            onPressed: () => showSpaceSheet<void>(
                              context,
                              AlbumMembersSheet(albumId: album.id),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(switch (role) {
                        AlbumRole.owner => 'You choose this album’s cover, memories, and members.',
                        AlbumRole.contributor =>
                          'Add memories and remove your own additions.',
                        _ => 'You can enjoy this collection. An owner can change your role.',
                      }, style: text.bodyMedium),
                      SpaceSection(
                        'The good times',
                        detail: '${photos.length} memories',
                      ),
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
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
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
                    key: ValueKey('album-memory-${photo.id}'),
                    media: photo,
                    selected: selecting ? selected.contains(photo.id) : null,
                    subtitle: album.shared
                        ? repository.memberById(album.addedBy[photo.id]!).name
                        : null,
                    onLongPress: canAdd ? () => toggle(photo.id) : null,
                    onTap: selecting
                        ? () => toggle(photo.id)
                        : () => openMediaViewer(
                            context,
                            mediaIds: photos.map((item) => item.id).toList(),
                            initialId: photo.id,
                          ),
                  );
                },
              ),
            ),
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
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final album = repository.albums
        .where((item) => item.id == widget.albumId)
        .firstOrNull;
    final available = repository.media
        .where((item) => album != null && !album.mediaIds.contains(item.id))
        .toList();
    final photos = available
        .where(
          (item) => item.title.toLowerCase().contains(
            search.text.trim().toLowerCase(),
          ),
        )
        .toList();
    final ids = selected
        .where((id) => available.any((item) => item.id == id))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Add memories')),
      body: CustomScrollView(
        key: const ValueKey('album-picker-scroll'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: TextField(
                key: const ValueKey('album-photo-search'),
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Find a memory',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
          padding: const EdgeInsets.all(16),
          child: SpaceButton(
            key: const ValueKey('save-album-photos'),
            label:
                'Add ${ids.length} ${ids.length == 1 ? 'memory' : 'memories'}',
            icon: Icons.add_rounded,
            onPressed: ids.isEmpty || repository.pendingWrites > 0
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

class AlbumMembersSheet extends StatelessWidget {
  final String albumId;
  const AlbumMembersSheet({super.key, required this.albumId});
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final album = repository.albums
        .where((item) => item.id == albumId)
        .firstOrNull;
    if (album == null) return const Text('This album is unavailable.');
    final owner = album.roleFor(repository.profile.userId) == AlbumRole.owner;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The people in this story',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          'Local sharing preview. Changes stay on this device; no invitations are sent.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final membership in album.memberships)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: SpaceStyle.of(context).accentSoft,
              foregroundColor: SpaceStyle.of(context).accentInk,
              child: Text(repository.memberById(membership.userId).initial),
            ),
            title: Text(
              '${repository.memberById(membership.userId).name}${membership.userId == repository.profile.userId ? ' (you)' : ''}',
            ),
            subtitle: Text(switch (membership.role) {
              AlbumRole.owner => 'Owner · Manages this album',
              AlbumRole.contributor => 'Contributor · Adds memories',
              AlbumRole.viewer => 'Viewer · Enjoys memories',
            }),
            trailing: !owner || membership.role == AlbumRole.owner
                ? null
                : PopupMenuButton<String>(
                    key: ValueKey('member-options-${membership.userId}'),
                    tooltip:
                        'Change ${repository.memberById(membership.userId).name}’s role',
                    enabled: repository.pendingWrites == 0,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'viewer',
                        child: Text('Make viewer'),
                      ),
                      PopupMenuItem(
                        value: 'contributor',
                        child: Text('Make contributor'),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove member'),
                      ),
                    ],
                    onSelected: (action) async {
                      if (action == 'remove') {
                        final confirmed = await confirmLibraryAction(
                          context,
                          title: 'Remove this member?',
                          message: 'Their memories stay in the album. You can add this family member again later.',
                          confirm: 'Remove member',
                        );
                        if (!confirmed || !context.mounted) return;
                        await saveLocalChange(
                          context,
                          () => repository.removeMember(
                            albumId,
                            membership.userId,
                          ),
                        );
                      } else {
                        await saveLocalChange(
                          context,
                          () => repository.setMemberRole(
                            albumId,
                            membership.userId,
                            action == 'viewer'
                                ? AlbumRole.viewer
                                : AlbumRole.contributor,
                          ),
                        );
                      }
                    },
                  ),
          ),
        if (owner &&
            repository.snapshot.family.any(
              (person) => album.roleFor(person.id) == null,
            )) ...[
          const SizedBox(height: 16),
          SpaceButton(
            key: const ValueKey('add-family-member'),
            label: 'Add family member',
            icon: Icons.person_add_alt_rounded,
            onPressed: repository.pendingWrites > 0
                ? null
                : () => showSpaceSheet<void>(
                    context,
                    AddFamilyMemberSheet(albumId: albumId),
                  ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

class AddFamilyMemberSheet extends StatefulWidget {
  final String albumId;
  const AddFamilyMemberSheet({super.key, required this.albumId});
  @override
  State<AddFamilyMemberSheet> createState() => _AddFamilyMemberSheetState();
}

class _AddFamilyMemberSheetState extends State<AddFamilyMemberSheet> {
  String? memberId;
  AlbumRole role = AlbumRole.viewer;
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final album = repository.albums
        .where((item) => item.id == widget.albumId)
        .firstOrNull;
    final people = repository.snapshot.family
        .where((person) => album?.roleFor(person.id) == null)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'A place for your people',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          'Choose a sample family member and their role in this album.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        for (final person in people)
          ListTile(
            key: ValueKey('choose-member-${person.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(person.name),
            trailing: Icon(
              memberId == person.id
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
            ),
            onTap: () => setState(() => memberId = person.id),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<AlbumRole>(
          key: const ValueKey('new-member-role'),
          initialValue: role,
          decoration: const InputDecoration(labelText: 'Album role'),
          items: const [
            DropdownMenuItem(value: AlbumRole.viewer, child: Text('Viewer')),
            DropdownMenuItem(
              value: AlbumRole.contributor,
              child: Text('Contributor'),
            ),
          ],
          onChanged: (value) =>
              setState(() => role = value ?? AlbumRole.viewer),
        ),
        const SizedBox(height: 20),
        SpaceButton(
          label: 'Add to this album',
          icon: Icons.person_add_alt_rounded,
          onPressed: memberId == null || repository.pendingWrites > 0
              ? null
              : () async {
                  final saved = await saveLocalChange(
                    context,
                    () => repository.setMemberRole(
                      widget.albumId,
                      memberId!,
                      role,
                    ),
                  );
                  if (saved && context.mounted) Navigator.pop(context);
                },
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
