import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/media_timeline.dart';
import '../domain/models.dart';
import 'library_widgets.dart';
import 'local_edit_sheets.dart';
import 'media_viewer.dart';

enum SmartCollectionType {
  favorites,
  videos,
  onDevice,
}

class SmartCollectionPage extends StatefulWidget {
  final SmartCollectionType type;
  const SmartCollectionPage({super.key, required this.type});

  @override
  State<SmartCollectionPage> createState() => _SmartCollectionPageState();
}

class _SmartCollectionPageState extends State<SmartCollectionPage> {
  bool selecting = false;
  final selected = <String>{};
  int selectionRevision = 0;

  void clear() => setState(() {
    selectionRevision++;
    selecting = false;
    selected.clear();
  });

  void toggle(String id) => setState(() {
    selectionRevision++;
    selecting = true;
    selected.contains(id) ? selected.remove(id) : selected.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final text = Theme.of(context).textTheme;
    final style = SpaceStyle.of(context);

    String title;
    IconData icon;
    Color accentColor;
    String emptyTitle;
    String emptyMessage;
    List<MediaItem> photos;

    switch (widget.type) {
      case SmartCollectionType.favorites:
        title = 'Favorites';
        icon = Icons.favorite_rounded;
        accentColor = const Color(0xFFFF4B6E);
        emptyTitle = 'No favorites yet';
        emptyMessage = 'Star your most precious moments to find them quickly here.';
        photos = repository.media
            .where((m) => repository.favorites.contains(m.id))
            .toList()
          ..sort(MediaItem.compareNewestFirst);
        break;

      case SmartCollectionType.videos:
        title = 'Videos';
        icon = Icons.videocam_rounded;
        accentColor = const Color(0xFF8B5CF6);
        emptyTitle = 'No videos yet';
        emptyMessage = 'Recorded video memories will appear together here.';
        photos = repository.media
            .where((m) => m.kind == MediaKind.video)
            .toList()
          ..sort(MediaItem.compareNewestFirst);
        break;

      case SmartCollectionType.onDevice:
        title = 'On Device';
        icon = Icons.phone_android_rounded;
        accentColor = const Color(0xFF10B981);
        emptyTitle = 'No local media';
        emptyMessage = 'Photos and videos stored directly on this phone will appear here.';
        photos = repository.media
            .where((m) => !m.isSynced || !m.asset.startsWith('http'))
            .toList()
          ..sort(MediaItem.compareNewestFirst);
        break;
    }

    final groups = groupMediaTimeline(photos, repository.groupFor);
    final ids = selected.where((id) => photos.any((item) => item.id == id)).toList();
    final allFavorite = ids.isNotEmpty && repository.favorites.containsAll(ids);
    final busy = repository.pendingWrites > 0;

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) clear();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(selecting ? '${ids.length} selected' : title),
          leading: selecting
              ? IconButton(
                  tooltip: 'Cancel selection',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: clear,
                )
              : null,
          actions: [
            if (selecting)
              IconButton(
                tooltip: 'Select all',
                icon: const Icon(Icons.select_all_rounded),
                onPressed: () => setState(() {
                  selectionRevision++;
                  selected.addAll(photos.map((item) => item.id));
                }),
              ),
          ],
          bottom: !selecting
              ? null
              : SelectionActions(
                  children: [
                    OutlinedButton.icon(
                      icon: Icon(
                        allFavorite
                            ? Icons.favorite_border_rounded
                            : Icons.favorite_rounded,
                      ),
                      label: Text(allFavorite ? 'Unfavorite' : 'Favorite'),
                      onPressed: ids.isEmpty || busy
                          ? null
                          : () async {
                              final revision = selectionRevision;
                              final saved = await saveLocalChange(
                                context,
                                () => repository.setFavorites(ids, !allFavorite),
                              );
                              if (saved && mounted && revision == selectionRevision) {
                                clear();
                              }
                            },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add to album'),
                      onPressed: ids.isEmpty || busy
                          ? null
                          : () async {
                              final revision = selectionRevision;
                              final saved = await showModalBottomSheet<bool>(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    20,
                                    16,
                                    20,
                                    spaceBottomPadding(context),
                                  ),
                                  child: AlbumPickerSheet(mediaIds: ids),
                                ),
                              );
                              if (saved == true && mounted && revision == selectionRevision) {
                                clear();
                              }
                            },
                    ),
                  ],
                ),
        ),
        body: photos.isEmpty
            ? Center(
                child: SpaceEmpty(
                  icon: icon,
                  title: emptyTitle,
                  message: emptyMessage,
                ),
              )
            : CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: accentColor, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${photos.length} ${photos.length == 1 ? 'memory' : 'memories'}',
                            style: text.bodyMedium?.copyWith(
                              color: style.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final group in groups.entries) ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: SpaceSection(
                          group.key,
                          detail:
                              '${group.value.length} ${group.value.length == 1 ? 'memory' : 'memories'}',
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
                        itemCount: group.value.length,
                        itemBuilder: (context, index) {
                          final photo = group.value[index];
                          return MemoryTile(
                            key: ValueKey('smart-${photo.id}'),
                            media: photo,
                            selected: selecting ? selected.contains(photo.id) : null,
                            favorite: repository.favorites.contains(photo.id),
                            onTap: () {
                              if (selecting) {
                                toggle(photo.id);
                                return;
                              }
                              openSpacePage(
                                context,
                                MediaViewer(
                                  mediaIds: photos.map((m) => m.id).toList(),
                                  initialId: photo.id,
                                ),
                              );
                            },
                            onLongPress: () => toggle(photo.id),
                          );
                        },
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: SizedBox(height: spaceBottomPadding(context)),
                  ),
                ],
              ),
      ),
    );
  }
}
