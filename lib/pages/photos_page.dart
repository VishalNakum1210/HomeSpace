import 'package:flutter/material.dart';

import '../design/space_symbols.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../sample/sample_library.dart';

class PhotosPage extends StatefulWidget {
  final VoidCallback onProfile;
  const PhotosPage({super.key, required this.onProfile});
  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  final search = TextEditingController();
  final favorites = <int>{1, 2, 6};
  String filter = 'All';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = SpaceStyle.of(context);
    final query = search.text.trim().toLowerCase();
    final photos = samplePhotos
        .where(
          (photo) =>
              (filter == 'All' ||
                  (filter == 'Favorites'
                      ? favorites.contains(photo.id)
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
    return SafeArea(
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
                        icon: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: style.accentSoft,
                            border: Border.all(
                              color: style.accent.withValues(alpha: .5),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'M',
                              style: text.titleMedium!.copyWith(
                                color: style.accentInk,
                              ),
                            ),
                          ),
                        ),
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
                                'Sample library · Offline preview',
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
            const SliverToBoxAdapter(
              child: SpaceEmpty(
                icon: Icons.photo_library_outlined,
                title: 'A little quiet here',
                message: 'Try another search or choose a different filter.',
              ),
            ),
          for (final group in ['Today', 'Yesterday'])
            if (photos.any((photo) => photo.group == group)) ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: SpaceSection(
                    group,
                    detail:
                        '${photos.where((p) => p.group == group).length} memories',
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
                  itemCount: photos.where((p) => p.group == group).length,
                  itemBuilder: (context, index) {
                    final photo = photos
                        .where((p) => p.group == group)
                        .elementAt(index);
                    return Semantics(
                      label:
                          '${photo.title}, ${photo.group}${favorites.contains(photo.id) ? ', favorite' : ''}',
                      button: true,
                      child: Material(
                        color: style.accentSoft,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => openPhoto(photo),
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
                                if (favorites.contains(photo.id))
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
    );
  }

  Future<void> openPhoto(SamplePhoto photo) => showSpaceSheet<void>(
    context,
    StatefulBuilder(
      builder: (context, updateSheet) => Column(
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
            '${photo.group} · Sample photo',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 22),
          SpaceButton(
            label: favorites.contains(photo.id)
                ? 'Remove from favorites'
                : 'Add to favorites',
            icon: favorites.contains(photo.id)
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            onPressed: () {
              setState(
                () => favorites.contains(photo.id)
                    ? favorites.remove(photo.id)
                    : favorites.add(photo.id),
              );
              updateSheet(() {});
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
