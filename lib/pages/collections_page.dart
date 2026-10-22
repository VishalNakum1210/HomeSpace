import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import 'local_edit_sheets.dart';

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});
  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  String filter = 'All';
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final text = Theme.of(context).textTheme;
    final style = SpaceStyle.of(context);
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
                    const SpacePageHeading(
                      SpacePage.collections,
                      subtitle: 'Good times belong together.',
                    ),
                    SpaceCard(
                      color: style.accentSoft,
                      borderColor: style.accent.withValues(alpha: .35),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.people_alt_rounded,
                              color: style.accentInk,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'One family. Many stories.',
                                  style: text.titleMedium!.copyWith(
                                    color: style.accentInk,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Local albums. A little space for every adventure.',
                                  style: text.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
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
                    Row(
                      children: [
                        Expanded(
                          child: SpaceSection(
                            'Your collections',
                            detail: '${albums.length} albums',
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('new-album'),
                          tooltip: 'Create album',
                          icon: Icon(
                            Icons.add_circle_outline_rounded,
                            color: style.accentInk,
                          ),
                          onPressed: repository.scenario == DemoScenario.empty
                              ? null
                              : () => showSpaceSheet<void>(
                                  context,
                                  const AlbumNameSheet(),
                                ),
                        ),
                      ],
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
                                  onTap: () => showSpaceSheet<void>(
                                    context,
                                    AlbumPreviewSheet(
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
                child: Text(
                  'Albums saved on this device · Sharing is a demo',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AlbumPreviewSheet extends StatelessWidget {
  final String albumId;
  const AlbumPreviewSheet({super.key, required this.albumId});
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    Album? album;
    for (final candidate in repository.albums) {
      if (candidate.id == albumId) album = candidate;
    }
    if (album == null) {
      return const SpaceEmpty(
        icon: Icons.photo_album_outlined,
        title: 'This album is unavailable',
        message: 'Return to Collections and try again.',
      );
    }
    final photos = repository.photosFor(album);
    final members = [
      for (final member in album.memberships)
        repository.memberById(member.userId).initial,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SpaceBadge(album.shared ? 'SHARED ALBUM' : 'MY ALBUM'),
            const SpaceBadge('LOCAL DEMO'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                album.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            if (album.roleFor(repository.profile.userId) == AlbumRole.owner)
              IconButton(
                key: const ValueKey('rename-album'),
                tooltip: 'Rename album',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    showSpaceSheet<void>(context, AlbumNameSheet(album: album)),
              ),
          ],
        ),
        if (album.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(album.description, style: Theme.of(context).textTheme.bodyLarge),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            _Members(members: members),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                album.shared
                    ? 'A space for ${members.length} family members'
                    : 'A little collection of your own',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Your role: ${album.roleFor(repository.profile.userId)!.name}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        if (photos.isEmpty)
          const SpaceEmpty(
            icon: Icons.photo_album_outlined,
            title: 'Room for new memories',
            message: 'Open a photo and add it to this album.',
          ),
        for (var row = 0; row < (photos.length / 2).ceil(); row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var column = 0; column < 2; column++) ...[
                  if (column > 0) const SizedBox(width: 8),
                  Expanded(
                    child: row * 2 + column < photos.length
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: AspectRatio(
                              aspectRatio: 1.2,
                              child: Image.asset(
                                photos[row * 2 + column].asset,
                                fit: BoxFit.cover,
                                cacheWidth: 600,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final Album album;
  final HomeRepository repository;
  final VoidCallback onTap;
  const _AlbumCard({
    required this.album,
    required this.repository,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    final text = Theme.of(context).textTheme;
    final cover = repository.coverFor(album);
    final photos = repository.photosFor(album);
    return Semantics(
      button: true,
      label:
          '${album.title}, ${photos.length} photos, ${album.shared ? 'shared' : 'personal'} album',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: style.border, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('album-${album.id}'),
          onTap: onTap,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1.15,
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
                          left: 10,
                          bottom: 10,
                          child: _Members(
                            members: [
                              for (final member in album.memberships)
                                repository.memberById(member.userId).initial,
                            ],
                            small: true,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
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
