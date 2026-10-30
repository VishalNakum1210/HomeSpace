import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/cartoon_header.dart';
import '../design/cartoon_artwork.dart';
import '../design/album_widgets.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import 'album_page.dart';
import 'library_widgets.dart';
import 'album_editor_page.dart';

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
                              const SizedBox(height: 5),
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
                    const SizedBox(height: 12),
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
                  onPressed: repository.scenario == DemoScenario.empty
                      ? null
                      : () => openAlbumEditor(context),
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
                          Image.asset(
                            cover.asset,
                            fit: BoxFit.cover,
                            cacheWidth: 600,
                          ),
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
