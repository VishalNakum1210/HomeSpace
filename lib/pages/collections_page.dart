import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/cartoon_header.dart';
import '../design/cartoon_artwork.dart';
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
                                selected: filter == label,
                                onTap: () => setState(() => filter = label),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 4),
                      child: Text(
                        '${albums.length} albums',
                        style: text.bodyMedium,
                      ),
                    ),
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
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0) const SizedBox(width: 14),
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
    final tint = [
      const Color(0xFFFFE4E7),
      const Color(0xFFEFE2FF),
      const Color(0xFFDDF1FF),
      const Color(0xFFE8F6D6),
    ][tintIndex % 4];
    final cardColor = Theme.of(context).brightness == Brightness.dark
        ? Color.alphaBlend(
            tint.withValues(alpha: .12),
            Theme.of(context).colorScheme.surfaceContainer,
          )
        : tint;
    return Semantics(
      button: true,
      label:
          '${album.title}, ${photos.length} photos, ${album.shared ? 'shared' : 'personal'} album',
      child: Material(
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('album-${album.id}'),
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 1.1,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (cover == null)
                            ColoredBox(
                              color: style.accentSoft,
                              child: Icon(
                                Icons.photo_album_outlined,
                                size: 42,
                                color: style.accentInk,
                              ),
                            )
                          else
                            Image.asset(
                              cover.asset,
                              fit: BoxFit.cover,
                              cacheWidth: 600,
                            ),
                          if (album.shared)
                            Positioned(
                              top: 7,
                              left: 7,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xEEFFFFFF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.people_alt_rounded,
                                      size: 12,
                                      color: Color(0xFF42445C),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Shared',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF42445C),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (album.shared)
                            Positioned(
                              left: 10,
                              bottom: 10,
                              child: _Members(
                                members: [
                                  for (final member in album.memberships)
                                    repository
                                        .memberById(member.userId)
                                        .initial,
                                ],
                                small: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 9, 4, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          album.title,
                          style: text.titleMedium!.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${photos.length} photos · ${album.shared ? 'Shared' : 'Just you'}',
                          style: text.bodyMedium!.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
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

class _Members extends StatelessWidget {
  final List<String> members;
  final bool small;
  const _Members({required this.members, this.small = false});
  @override
  Widget build(BuildContext context) {
    final diameter = small ? 25.0 : 34.0;
    return SizedBox(
      width: diameter + (members.length - 1) * diameter * .7,
      height: diameter,
      child: Stack(
        children: [
          for (var i = 0; i < members.length; i++)
            Positioned(
              left: i * diameter * .7,
              child: Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: [
                    const Color(0xFFEEDCFF),
                    const Color(0xFFFFE0B3),
                    const Color(0xFFD9EDFC),
                  ][i % 3],
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    members[i],
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w900,
                      fontSize: small ? 10 : 13,
                      color: const Color(0xFF554366),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
