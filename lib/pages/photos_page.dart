import 'package:flutter/material.dart';

import '../design/vector_artwork.dart';

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
  final ValueChanged<bool>? onFocusChanged;
  const PhotosPage({
    super.key,
    required this.onProfile,
    this.active = true,
    this.onFocusChanged,
  });
  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _EmptyPhotoLibrary extends StatelessWidget {
  final VoidCallback onProfile;
  const _EmptyPhotoLibrary({required this.onProfile});
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, spaceBottomPadding(context)),
        child: Column(
          children: [
            CartoonHeader(profile: repository.profile, onProfile: onProfile),
            SpaceArtwork(
              'empty-garden',
              height: 172,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),
            Text(
              'Your memories start here',
              style: text.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add photos, people and places\nthat matter most.',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SpaceButton(
              key: const ValueKey('add-photos'),
              label: 'Add photos',
              icon: Icons.add_circle_outline_rounded,
              backgroundColor: const Color(0xFF1677E8),
              foregroundColor: Colors.white,
              onPressed: () => showSpaceSheet<void>(
                context,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Add photos', style: text.titleLarge),
                    const SizedBox(height: 12),
                    const Text(
                      'This frontend preview uses sample photos. Device import and home-server uploads are not connected yet.',
                    ),
                    const SizedBox(height: 18),
                    if (repository.scenario == DemoScenario.empty)
                      SpaceButton(
                        label: 'Explore sample library',
                        onPressed: () {
                          Navigator.pop(context);
                          repository.setScenario(DemoScenario.populated);
                        },
                      )
                    else
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            MemoryStatusBanner(
              warning: true,
              message: repository.scenario == DemoScenario.offline
                  ? "You’re offline\nSaved photos are available."
                  : 'Local preview\nYour saved library is kept.',
              onRetry: () => repository.setScenario(DemoScenario.populated),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotosPageState extends State<PhotosPage> {
  final search = TextEditingController();
  String filter = 'All';
  bool selecting = false;
  bool searching = false;
  final selected = <String>{};
  int selectionRevision = 0;
  void changeMode(VoidCallback update) {
    setState(update);
    widget.onFocusChanged?.call(selecting || searching);
  }

  void clearSelection() => changeMode(() {
    selectionRevision++;
    selecting = false;
    selected.clear();
  });
  void closeSearch() {
    FocusScope.of(context).unfocus();
    changeMode(() {
      searching = false;
      search.clear();
    });
  }

  void toggle(String id) => changeMode(() {
    selectionRevision++;
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
    if (repository.media.isEmpty && !focused) {
      return ScenarioContent(
        repository: repository,
        child: _EmptyPhotoLibrary(onProfile: widget.onProfile),
      );
    }
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
                            ),
                            Text(
                              'Your happy place',
                              style: text.headlineMedium,
                            ),
                            const SizedBox(height: 5),
                            Stack(
                              children: [
                                const MemoryGarden(),
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  width: MediaQuery.sizeOf(context).width * .58,
                                  child: Text(
                                    'Photos, people and places\nthat matter most.',
                                    style: text.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
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
                              if (focused)
                                IconButton(
                                  tooltip: selecting
                                      ? 'Cancel selection'
                                      : 'Close search',
                                  onPressed: selecting
                                      ? clearSelection
                                      : closeSearch,
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                              Expanded(
                                key: const ValueKey('search-entry'),
                                child: TextField(
                                  key: const ValueKey('photo-search'),
                                  controller: search,
                                  onTap: () {
                                    if (!searching) {
                                      changeMode(() => searching = true);
                                    }
                                  },
                                  onChanged: (_) => changeMode(
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
                                        icon: label == 'Favorites'
                                            ? Icons.favorite_border_rounded
                                            : label == 'Videos'
                                            ? Icons.play_arrow_outlined
                                            : null,
                                        selected: filter == label,
                                        onTap: () =>
                                            changeMode(() => filter = label),
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
                  if (focused)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                header: true,
                                label: 'Search results',
                                child: Text(
                                  '${photos.length} ${photos.length == 1 ? 'result' : 'results'}',
                                  key: const ValueKey('search-result-summary'),
                                  style: text.bodyMedium,
                                ),
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF1267D2),
                              ),
                              onPressed: photos.isEmpty
                                  ? null
                                  : () => changeMode(() {
                                      selectionRevision++;
                                      selecting = true;
                                      selected.addAll(
                                        photos.map((photo) => photo.id),
                                      );
                                    }),
                              child: const Text('Select all'),
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
                    if (!focused)
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
                  bottom: 12 + MediaQuery.paddingOf(context).bottom,
                  child: SpaceCard(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${ids.length} selected',
                                style: text.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cancel selection',
                              onPressed: clearSelection,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
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
                                        final revision = selectionRevision;
                                        final saved = await saveLocalChange(
                                          context,
                                          () => repository.setFavorites(
                                            ids,
                                            !allFavorite,
                                          ),
                                        );
                                        if (saved &&
                                            mounted &&
                                            revision == selectionRevision) {
                                          clearSelection();
                                        }
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
                                        final revision = selectionRevision;
                                        final saved =
                                            await showSpaceSheet<bool>(
                                              context,
                                              AlbumPickerSheet(mediaIds: ids),
                                            );
                                        if (saved == true &&
                                            mounted &&
                                            revision == selectionRevision) {
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
                                        final revision = selectionRevision;
                                        final saved = await trashMemories(
                                          context,
                                          ids,
                                        );
                                        if (saved &&
                                            mounted &&
                                            revision == selectionRevision) {
                                          clearSelection();
                                        }
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
