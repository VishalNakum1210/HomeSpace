import 'package:flutter/material.dart';

import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../sample/sample_library.dart';

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});
  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  String filter = 'All';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = SpaceStyle.of(context);
    final albums = sampleAlbums
        .where(
          (album) =>
              filter == 'All' ||
              (filter == 'Shared' ? album.shared : !album.shared),
        )
        .toList();
    final columns = MediaQuery.sizeOf(context).width >= 700 ? 3 : 2;
    return SafeArea(
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
                          child: const Icon(
                            Icons.people_alt_rounded,
                            color: Color(0xFF9451D8),
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
                                'A little space for every adventure.',
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
                  SpaceSection(
                    'Your collections',
                    detail: '${albums.length} albums',
                  ),
                ],
              ),
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
                                onTap: () =>
                                    openAlbum(albums[row * columns + column]),
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
                'Sample albums · Sharing comes in a later phase',
                textAlign: TextAlign.center,
                style: text.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> openAlbum(SampleAlbum album) => showSpaceSheet<void>(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SpaceBadge(album.shared ? 'SHARED ALBUM' : 'MY ALBUM'),
            const SpaceBadge('PREVIEW'),
          ],
        ),
        const SizedBox(height: 16),
        Text(album.title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(album.subtitle, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 20),
        Row(
          children: [
            _Members(members: album.members),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                album.shared
                    ? 'A space for ${album.members.length} family members'
                    : 'A little collection of your own',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        for (var row = 0; row < (album.photos.length / 2).ceil(); row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var column = 0; column < 2; column++) ...[
                  if (column > 0) const SizedBox(width: 8),
                  Expanded(
                    child: row * 2 + column < album.photos.length
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: AspectRatio(
                              aspectRatio: 1.2,
                              child: Image.asset(
                                samplePhotos[album.photos[row * 2 + column] - 1]
                                    .asset,
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
    ),
  );
}

class _AlbumCard extends StatelessWidget {
  final SampleAlbum album;
  final VoidCallback onTap;
  const _AlbumCard({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label:
          '${album.title}, ${album.photos.length} photos, ${album.shared ? 'shared' : 'personal'} album',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: style.border, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
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
                      Image.asset(
                        album.cover.asset,
                        fit: BoxFit.cover,
                        cacheWidth: 600,
                      ),
                      if (album.shared)
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: _Members(members: album.members, small: true),
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
                        '${album.photos.length} photos · ${album.shared ? 'Shared' : 'Just you'}',
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
