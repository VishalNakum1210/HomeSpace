import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/cartoon_artwork.dart';
import '../design/cartoon_header.dart';
import '../design/space_theme.dart';
import '../design/photo_action.dart';
import '../design/state_artwork.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import 'library_widgets.dart';
import 'local_edit_sheets.dart';
import 'media_viewer.dart';

class PhotosPage extends StatefulWidget {
  final VoidCallback onProfile;
  final bool active;
  const PhotosPage({super.key, required this.onProfile, this.active = true});
  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  final search = TextEditingController();
  String filter = 'All';
  bool selecting = false;
  bool searching = false;
  final selected = <String>{};
  void clearSelection() => setState(() {
    selecting = false;
    selected.clear();
  });
  void closeSearch() {
    FocusScope.of(context).unfocus();
    setState(() {
      searching = false;
      search.clear();
    });
  }

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
                      : filter == 'Videos'
                      ? photo.kind == MediaKind.video
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
    final focused = selecting || searching;
    return PopScope(
      canPop: !widget.active || (!selecting && !searching),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.active) {
          if (selecting) {
            clearSelection();
          } else if (searching) {
            closeSearch();
          }
        }
      },
      child: ScenarioContent(
        repository: repository,
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              CustomScrollView(
                key: const PageStorageKey('photos-scroll'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                            () =>
                                selected.addAll(photos.map((item) => item.id)),
                          ),
                        ),
                      ],
                    ),
                  SliverPadding(
                    key: const ValueKey('photos-header'),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!focused) ...[
                            CartoonHeader(
                              profile: repository.profile,
                              onProfile: widget.onProfile,
                              action: IconButton(
                                tooltip: 'Select photos',
                                onPressed: () =>
                                    setState(() => selecting = true),
                                icon: const Icon(Icons.checklist_rounded),
                              ),
                            ),
                            Text(
                              'Your happy place',
                              style: text.headlineMedium,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Photos, people and places that matter most.',
                              style: text.bodyMedium,
                            ),
                            const MemoryGarden(),
                            if (repository.scenario == DemoScenario.offline ||
                                repository.scenario == DemoScenario.success ||
                                repository.recoveryNotice != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: MemoryStatusBanner(
                                  message: libraryStatus(repository),
                                  onRetry:
                                      repository.scenario ==
                                          DemoScenario.offline
                                      ? () => repository.setScenario(
                                          DemoScenario.populated,
                                        )
                                      : null,
                                ),
                              ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            key: const ValueKey('photo-search-row'),
                            children: [
                              if (searching && !selecting)
                                IconButton(
                                  tooltip: 'Close search',
                                  onPressed: closeSearch,
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                              Expanded(
                                key: const ValueKey('search-entry'),
                                child: TextField(
                                  key: const ValueKey('photo-search'),
                                  controller: search,
                                  onTap: () {
                                    if (!searching) {
                                      setState(() => searching = true);
                                    }
                                  },
                                  onChanged: (_) => setState(
                                    () => searching = search.text.isNotEmpty,
                                  ),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).unfocus(),
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
                                            onPressed: closeSearch,
                                            icon: const Icon(
                                              Icons.close_rounded,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (!focused) ...[
                            const SizedBox(height: 16),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final label in [
                                    'All',
                                    'Favorites',
                                    'Videos',
                                  ])
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: SpaceFilter(
                                        label: label,
                                        selected: filter == label,
                                        onTap: () =>
                                            setState(() => filter = label),
                                      ),
                                    ),
                                ],
                              ),
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
                        title: repository.media.isEmpty
                            ? 'Your memories start here'
                            : 'A little quiet here',
                        action: repository.scenario == DemoScenario.empty
                            ? SpaceButton(
                                label: 'Explore sample library',
                                onPressed: () => repository.setScenario(
                                  DemoScenario.populated,
                                ),
                              )
                            : null,
                        message: repository.media.isEmpty
                            ? repository.scenario == DemoScenario.empty
                                  ? 'Your saved library is safe. Explore the sample memories when you are ready.'
                                  : 'Photos you add will appear here, all together.'
                            : 'Try another search or choose a different filter.',
                      ),
                    ),
                  for (final group
                      in focused
                          ? {'Search results'}
                          : photos.map(repository.groupFor).toSet()) ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: SpaceSection(
                          group,
                          detail: focused
                              ? '${photos.length} ${photos.length == 1 ? 'result' : 'results'}'
                              : '${photos.where((item) => repository.groupFor(item) == group).length} memories',
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                        itemCount: photos
                            .where(
                              (item) =>
                                  focused || repository.groupFor(item) == group,
                            )
                            .length,
                        itemBuilder: (context, index) {
                          final photo = photos
                              .where(
                                (item) =>
                                    focused ||
                                    repository.groupFor(item) == group,
                              )
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
                        spaceBottomPadding(context) + (selecting ? 200 : 0),
                      ),
                      child: focused
                          ? const SizedBox.shrink()
                          : Text(
                              'The little moments. All together.',
                              textAlign: TextAlign.center,
                              style: text.bodyMedium,
                            ),
                    ),
                  ),
                ],
              ),
              if (selecting)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 100 + MediaQuery.paddingOf(context).bottom,
                  child: SpaceCard(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: PhotoAction(
                                filled: true,
                                key: const ValueKey('bulk-favorite'),
                                icon: allFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_outline_rounded,
                                tone: const Color(0xFFE95470),
                                tooltip: allFavorite
                                    ? 'Unfavorite selected photos'
                                    : 'Favorite selected photos',
                                label: allFavorite ? 'Unfavorite' : 'Favorite',
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
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: PhotoAction(
                                filled: true,
                                key: const ValueKey('bulk-album'),
                                icon: Icons.add_photo_alternate_outlined,
                                tooltip: 'Add selected photos to album',
                                label: 'Add to album',
                                onPressed: !enabled
                                    ? null
                                    : () async {
                                        final saved =
                                            await showSpaceSheet<bool>(
                                              context,
                                              AlbumPickerSheet(mediaIds: ids),
                                            );
                                        if (saved == true && mounted) {
                                          clearSelection();
                                        }
                                      },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: PhotoAction(
                                filled: true,
                                key: const ValueKey('bulk-trash'),
                                icon: Icons.delete_outline_rounded,
                                tone: const Color(0xFFE74742),
                                tooltip: 'Move selected photos to Trash',
                                label: 'Trash',
                                onPressed: !enabled
                                    ? null
                                    : () async {
                                        final saved = await trashMemories(
                                          context,
                                          ids,
                                        );
                                        if (saved && mounted) clearSelection();
                                      },
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              key: const ValueKey('clear-photo-selection'),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .onSurface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: clearSelection,
                              child: const Text('Clear selection'),
                            ),
                          ),
                        ),
                      ],
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
