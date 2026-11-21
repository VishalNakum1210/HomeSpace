import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/album_widgets.dart';
import '../design/cartoon_artwork.dart';
import '../design/cartoon_header.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import 'album_editor_page.dart';
import 'album_page.dart';
import 'library_widgets.dart';
import 'smart_collection_page.dart';

class CollectionsPage extends StatefulWidget {
  final VoidCallback? onProfile;
  const CollectionsPage({super.key, this.onProfile});
  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  String filter = 'All';
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final text = Theme.of(context).textTheme;
    final albums = repository.albums
        .where(
          (album) =>
              filter == 'All' ||
              (filter == 'Shared' ? album.shared : !album.shared),
        )
        .toList();
    final columns = MediaQuery.sizeOf(context).width >= 700 ? 3 : 2;
    return ScenarioContent(
      repository: repository,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('collections-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CartoonHeader(
                      profile: repository.profile,
                      onProfile: widget.onProfile,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Collections', style: text.headlineMedium),
                              const SizedBox(height: 4),
                              Text(
                                'Little moments, together.',
                                style: text.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const AlbumSticker(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _SmartFoldersRow(repository: repository),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final label in ['All', 'Shared', 'Mine'])
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: SpaceFilter(
                                label: label,
                                icon: label == 'Shared'
                                    ? Icons.people_outline_rounded
                                    : label == 'Mine'
                                    ? Icons.person_outline_rounded
                                    : null,
                                selected: filter == label,
                                onTap: () => setState(() => filter = label),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            if (albums.isEmpty)
              const SliverToBoxAdapter(
                child: SpaceEmpty(
                  icon: Icons.collections_bookmark_outlined,
                  title: 'Stories start here',
                  message: 'Create an album to give your memories a place of their own.',
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: (albums.length / columns).ceil(),
                itemBuilder: (context, row) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0) const SizedBox(width: 10),
                        Expanded(
                          child: row * columns + column < albums.length
                              ? _AlbumCard(
                                  album: albums[row * columns + column],
                                  repository: repository,
                                  tintIndex: row * columns + column,
                                  onTap: () => openSpacePage<void>(
                                    context,
                                    AlbumPage(
                                      albumId:
                                          albums[row * columns + column].id,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  6,
                  20,
                  spaceBottomPadding(context),
                ),
                child: SpaceButton(
                  key: const ValueKey('new-album'),
                  label: 'Create album',
                  icon: Icons.add_photo_alternate_outlined,
                  onPressed: () => openAlbumEditor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final Album album;
  final HomeRepository repository;
  final VoidCallback onTap;
  final int tintIndex;
  const _AlbumCard({
    required this.album,
    required this.repository,
    required this.onTap,
    required this.tintIndex,
  });
  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    final text = Theme.of(context).textTheme;
    final cover = repository.coverFor(album);
    final photos = repository.photosFor(album);
    final owner = album.roleFor(repository.profile.userId) == AlbumRole.owner;
    final tint = [
      const Color(0xFFFFE4E7),
      const Color(0xFFEFE2FF),
      const Color(0xFFDDF1FF),
      const Color(0xFFE8F6D6),
    ][tintIndex % 4];
    final color = Theme.of(context).brightness == Brightness.dark
        ? Color.alphaBlend(
            tint.withValues(alpha: .12),
            Theme.of(context).colorScheme.surfaceContainer,
          )
        : tint;
    return Semantics(
      container: true,
      label: '${album.title}, ${photos.length} photos',
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('album-${album.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 1.35,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cover == null)
                          ColoredBox(
                            color: style.accentSoft,
                            child: Icon(
                              Icons.photo_album_outlined,
                              color: style.accentInk,
                            ),
                          )
                        else
                          MediaThumbnail(media: cover),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: AlbumPeople(
                            members: [
                              for (final membership in album.memberships)
                                repository.memberById(membership.userId),
                            ],
                          ),
                        ),
                        if (cover != null &&
                            repository.favorites.contains(cover.id))
                          const Positioned(
                            right: 5,
                            top: 5,
                            child: Icon(
                              Icons.favorite_border_rounded,
                              color: Colors.white,
                              size: 24,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 3),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: 3,
                            top: 5,
                            bottom: 5,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                album.title,
                                style: text.titleMedium!.copyWith(fontSize: 14),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${photos.length} memories',
                                style: text.bodyMedium!.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Options for ${album.title}',
                        enabled: repository.pendingWrites == 0,
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'open',
                            child: Text('Open album'),
                          ),
                          if (owner)
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit album'),
                            ),
                          if (owner)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete album'),
                            ),
                        ],
                        onSelected: (action) async {
                          if (action == 'open') {
                            onTap();
                            return;
                          }
                          if (action == 'edit') {
                            await openAlbumEditor(context, album: album);
                            return;
                          }
                          final confirmed = await confirmLibraryAction(
                            context,
                            title: 'Delete this album?',
                            message: 'Its photos stay in your library and other albums.',
                            confirm: 'Delete album',
                            destructive: true,
                          );
                          if (confirmed && context.mounted) {
                            await saveLocalChange(
                              context,
                              () => repository.deleteAlbum(album.id),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmartFoldersRow extends StatelessWidget {
  final HomeRepository repository;
  const _SmartFoldersRow({required this.repository});

  @override
  Widget build(BuildContext context) {
    final favCount = repository.media
        .where((m) => repository.favorites.contains(m.id))
        .length;
    final videoCount = repository.media
        .where((m) => m.kind == MediaKind.video)
        .length;
    final deviceCount = repository.media
        .where((m) => !m.isSynced || !m.asset.startsWith('http'))
        .length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SmartFolderCard(
            key: const ValueKey('smart-tile-favorites'),
            label: 'Favorites',
            subtitle: '$favCount memories',
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFFF4B6E),
            bgColor: const Color(0xFFFFE8EC),
            onTap: () => openSpacePage<void>(
              context,
              const SmartCollectionPage(type: SmartCollectionType.favorites),
            ),
          ),
          const SizedBox(width: 10),
          _SmartFolderCard(
            key: const ValueKey('smart-tile-videos'),
            label: 'Videos',
            subtitle: '$videoCount videos',
            icon: Icons.videocam_rounded,
            iconColor: const Color(0xFF8B5CF6),
            bgColor: const Color(0xFFF3E8FF),
            onTap: () => openSpacePage<void>(
              context,
              const SmartCollectionPage(type: SmartCollectionType.videos),
            ),
          ),
          const SizedBox(width: 10),
          _SmartFolderCard(
            key: const ValueKey('smart-tile-device'),
            label: 'On Device',
            subtitle: '$deviceCount items',
            icon: Icons.phone_android_rounded,
            iconColor: const Color(0xFF10B981),
            bgColor: const Color(0xFFD1FAE5),
            onTap: () => openSpacePage<void>(
              context,
              const SmartCollectionPage(type: SmartCollectionType.onDevice),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartFolderCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback onTap;

  const _SmartFolderCard({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? Color.alphaBlend(
            bgColor.withValues(alpha: 0.15),
            Theme.of(context).colorScheme.surfaceContainer,
          )
        : bgColor;

    return Semantics(
      button: true,
      label: '$label, $subtitle',
      child: Material(
        color: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        fontSize: 10,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
