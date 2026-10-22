import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_symbols.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import 'local_edit_sheets.dart';

class PhotosPage extends StatefulWidget {
  final VoidCallback onProfile;
  const PhotosPage({super.key, required this.onProfile});
  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  final search = TextEditingController();
  String filter = 'All';
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
    final columns =
        MediaQuery.sizeOf(context).width < 340 ||
            MediaQuery.textScalerOf(context).scale(16) > 25
        ? 2
        : MediaQuery.sizeOf(context).width > 650
        ? 5
        : 3;
    return ScenarioContent(
      repository: repository,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('photos-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
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
                    return Semantics(
                      label:
                          '${photo.title}, $group${repository.favorites.contains(photo.id) ? ', favorite' : ''}',
                      button: true,
                      child: Material(
                        color: style.accentSoft,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: ValueKey('memory-${photo.id}'),
                          onTap: () => showSpaceSheet<void>(
                            context,
                            PhotoPreviewSheet(photo: photo),
                          ),
                          child: ExcludeSemantics(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(
                                  photo.asset,
                                  fit: BoxFit.cover,
                                  cacheWidth: 440,
                                  errorBuilder: (_, _, _) => Icon(
                                    Icons.photo_outlined,
                                    color: style.accentInk,
                                  ),
                                ),
                                if (repository.favorites.contains(photo.id))
                                  const Positioned(
                                    right: 7,
                                    top: 7,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Color(0x88000000),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.all(5),
                                        child: Icon(
                                          Icons.favorite_rounded,
                                          size: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
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
    );
  }
}

class PhotoPreviewSheet extends StatelessWidget {
  final MediaItem photo;
  const PhotoPreviewSheet({super.key, required this.photo});
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final favorite = repository.favorites.contains(photo.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 1.25,
            child: Image.asset(photo.asset, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 20),
        Text(photo.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          '${repository.groupFor(photo)} · Sample photo',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 22),
        SpaceButton(
          key: const ValueKey('toggle-favorite'),
          label: favorite ? 'Remove from favorites' : 'Add to favorites',
          icon: favorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          onPressed: repository.pendingWrites > 0
              ? null
              : () => saveLocalChange(
                  context,
                  () => repository.toggleFavorite(photo.id),
                ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('choose-album'),
            icon: const Icon(Icons.collections_bookmark_outlined),
            label: const Text('Add to an album'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
            onPressed: () => showSpaceSheet<void>(
              context,
              AlbumPickerSheet(mediaId: photo.id),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
