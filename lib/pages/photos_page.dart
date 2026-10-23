import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_symbols.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import 'library_widgets.dart';
import 'local_edit_sheets.dart';
import 'media_viewer.dart';

class PhotosPage extends StatefulWidget {
  final VoidCallback onProfile;
  const PhotosPage({super.key, required this.onProfile});
  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  final search = TextEditingController();
  String filter = 'All';
  bool selecting = false;
  final selected = <String>{};
  void clearSelection() => setState(() {
    selecting = false;
    selected.clear();
  });
  void toggle(String id) => setState(() {
    selecting = true;
    selected.contains(id) ? selected.remove(id) : selected.add(id);
  });
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final text = Theme.of(context).textTheme;
    final style = SpaceStyle.of(context);
    final query = search.text.trim().toLowerCase();
    final photos = repository.media
        .where(
          (photo) =>
              (filter == 'All' ||
                  (filter == 'Favorites'
                      ? repository.favorites.contains(photo.id)
                      : photo.category == filter)) &&
              (query.isEmpty ||
                  photo.title.toLowerCase().contains(query) ||
                  photo.category.toLowerCase().contains(query)),
        )
        .toList();
    photos.sort((a, b) {
      final date = b.takenAt.compareTo(a.takenAt);
      return date == 0 ? a.id.compareTo(b.id) : date;
    });
    final columns = libraryColumns(context);
    final ids = selected
        .where((id) => repository.media.any((item) => item.id == id))
        .toList();
    final enabled = ids.isNotEmpty && repository.pendingWrites == 0;
    final allFavorite = ids.isNotEmpty && repository.favorites.containsAll(ids);
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) clearSelection();
      },
      child: ScenarioContent(
        repository: repository,
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            key: const PageStorageKey('photos-scroll'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              if (selecting)
                SliverAppBar(
                  pinned: true,
                  leading: IconButton(
                    tooltip: 'Cancel selection',
                    onPressed: clearSelection,
                    icon: const Icon(Icons.close_rounded),
                  ),
                  title: Text('${ids.length} selected'),
                  actions: [
                    IconButton(
                      tooltip: 'Select all visible photos',
                      icon: const Icon(Icons.select_all_rounded),
                      onPressed: () => setState(
                        () => selected.addAll(photos.map((item) => item.id)),
                      ),
                    ),
                  ],
                  bottom: SelectionActions(
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('bulk-favorite'),
                        icon: const Icon(Icons.favorite_outline_rounded),
                        label: Text(allFavorite ? 'Unfavorite' : 'Favorite'),
                        onPressed: !enabled
                            ? null
                            : () async {
                                final saved = await saveLocalChange(
                                  context,
                                  () => repository.setFavorites(
                                    ids,
                                    !allFavorite,
                                  ),
                                );
                                if (saved && mounted) clearSelection();
                              },
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('bulk-album'),
                        icon: const Icon(Icons.photo_album_outlined),
                        label: const Text('Add to album'),
                        onPressed: !enabled
                            ? null
                            : () async {
                                final saved = await showSpaceSheet<bool>(
                                  context,
                                  AlbumPickerSheet(mediaIds: ids),
                                );
                                if (saved == true && mounted) clearSelection();
                              },
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('bulk-trash'),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Trash'),
                        onPressed: !enabled
                            ? null
                            : () async {
                                final saved = await trashMemories(context, ids);
                                if (saved && mounted) clearSelection();
                              },
                      ),
                    ],
                  ),
                ),
              if (!selecting)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SpaceHouse(size: 43),
                            const SizedBox(width: 9),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'HomeSpace',
                                  maxLines: 1,
                                  style: text.headlineMedium!.copyWith(
                                    color: style.accentInk,
                                    fontSize: 27,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Select photos',
                              onPressed: () => setState(() => selecting = true),
                              icon: const Icon(Icons.checklist_rounded),
                            ),
                            IconButton(
                              tooltip: 'Open profile',
                              onPressed: widget.onProfile,
                              icon: ProfileAvatar(profile: repository.profile),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SpaceCard(
                          color: style.accentSoft,
                          borderColor: style.accent.withValues(alpha: .4),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const SpaceHouse(size: 45),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'A happy place for memories',
                                      style: text.titleMedium!.copyWith(
                                        color: style.accentInk,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      libraryStatus(repository),
                                      style: text.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          key: const ValueKey('photo-search'),
                          controller: search,
                          onChanged: (_) => setState(() {}),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                          decoration: InputDecoration(
                            hintText: 'Search your memories',
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: style.muted,
                            ),
                            suffixIcon: search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () => setState(search.clear),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final label in [
                                'All',
                                'People',
                                'Places',
                                'Favorites',
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: SpaceFilter(
                                    label: label,
                                    selected: filter == label,
                                    onTap: () => setState(() => filter = label),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (photos.isEmpty)
                SliverToBoxAdapter(
                  child: SpaceEmpty(
                    icon: Icons.photo_library_outlined,
                    title: repository.media.isEmpty
                        ? 'A home for new memories'
                        : 'A little quiet here',
                    message: repository.media.isEmpty
                        ? 'This empty preview keeps your saved library untouched.'
                        : 'Try another search or choose a different filter.',
                  ),
                ),
              for (final group in photos.map(repository.groupFor).toSet()) ...[
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: SpaceSection(
                      group,
                      detail:
                          '${photos.where((item) => repository.groupFor(item) == group).length} memories',
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: photos
                        .where((item) => repository.groupFor(item) == group)
                        .length,
                    itemBuilder: (context, index) {
                      final photo = photos
                          .where((item) => repository.groupFor(item) == group)
                          .elementAt(index);
                      return MemoryTile(
                        key: ValueKey('memory-${photo.id}'),
                        media: photo,
                        favorite: repository.favorites.contains(photo.id),
                        selected: selecting
                            ? selected.contains(photo.id)
                            : null,
                        onLongPress: () => toggle(photo.id),
                        onTap: selecting
                            ? () => toggle(photo.id)
                            : () => openMediaViewer(
                                context,
                                mediaIds: photos
                                    .map((item) => item.id)
                                    .toList(),
                                initialId: photo.id,
                              ),
                      );
                    },
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    24,
                    20,
                    spaceBottomPadding(context),
                  ),
                  child: Text(
                    'The little moments. All together.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
