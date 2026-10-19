import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';
import 'package:myspace/ui/core/widgets/photo_thumbnail.dart';
import 'package:myspace/ui/features/detail/photo_detail_screen.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PhotosViewModel>();
    final isSearching = vm.searchQuery.isNotEmpty ||
        vm.selectedTag != null ||
        vm.selectedPerson != null;
    final results = vm.filteredItems;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 14,
        title: Container(
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? PhotosColors.darkSurfaceVariant
                : PhotosColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(24),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => vm.setSearchQuery(val),
            decoration: InputDecoration(
              hintText: 'Search people, places, things...',
              prefixIcon: const Icon(Icons.search, size: 22),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        vm.setSearchQuery('');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
      body: isSearching
          ? _buildSearchResults(context, vm, results)
          : _buildExploreCategories(context, vm),
    );
  }

  Widget _buildSearchResults(BuildContext context, PhotosViewModel vm, dynamic results) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Active Filter Banner
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          child: Row(
            children: [
              Text(
                '${results.length} results',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (vm.selectedPerson != null)
                Chip(
                  label: Text('Person: ${vm.selectedPerson}'),
                  onDeleted: () => vm.setSelectedPerson(null),
                ),
              if (vm.selectedTag != null)
                Chip(
                  label: Text('Tag: ${vm.selectedTag}'),
                  onDeleted: () => vm.setSelectedTag(null),
                ),
            ],
          ),
        ),

        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off, size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('No photos matching search', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          _searchController.clear();
                          vm.clearAllFilters();
                        },
                        child: const Text('Clear search'),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(2),
                  itemCount: results.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemBuilder: (context, index) {
                    final item = results[index];
                    return PhotoThumbnail(
                      item: item,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PhotoDetailScreen(item: item)),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildExploreCategories(BuildContext context, PhotosViewModel vm) {
    final theme = Theme.of(context);

    final people = [
      {'name': 'Sophia', 'img': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=150&q=80'},
      {'name': 'Alex', 'img': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=150&q=80'},
      {'name': 'Liam', 'img': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=150&q=80'},
      {'name': 'Elena', 'img': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=150&q=80'},
      {'name': 'Noah', 'img': 'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?auto=format&fit=crop&w=150&q=80'},
    ];

    final places = [
      {'title': 'Tokyo', 'img': 'https://images.unsplash.com/photo-1519501025264-65ba15a82390?auto=format&fit=crop&w=300&q=80'},
      {'title': 'California', 'img': 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=300&q=80'},
      {'title': 'Alps', 'img': 'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=300&q=80'},
      {'title': 'New York', 'img': 'https://images.unsplash.com/photo-1514565131-fce0801e5785?auto=format&fit=crop&w=300&q=80'},
    ];

    final categories = [
      {'title': 'Mountains', 'icon': Icons.terrain, 'tag': 'Mountains'},
      {'title': 'Sunsets', 'icon': Icons.wb_twilight, 'tag': 'Sunset'},
      {'title': 'City & Streets', 'icon': Icons.location_city, 'tag': 'City'},
      {'title': 'Nature & Forests', 'icon': Icons.forest, 'tag': 'Nature'},
      {'title': 'Food & Dining', 'icon': Icons.restaurant, 'tag': 'Food'},
      {'title': 'Beaches & Oceans', 'icon': Icons.beach_access, 'tag': 'Beach'},
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      children: [
        // People & Pets Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'People & pets',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {},
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // People Avatars Row
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            itemBuilder: (ctx, i) {
              final p = people[i];
              return Padding(
                padding: const EdgeInsets.only(right: 14.0),
                child: GestureDetector(
                  onTap: () {
                    vm.setSelectedPerson(p['name']!);
                  },
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundImage: NetworkImage(p['img']!),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        p['name']!,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // Places Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Places',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Opening Google Photos Interactive Map...')),
                );
              },
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Your map'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Places Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: places.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.4,
          ),
          itemBuilder: (ctx, i) {
            final pl = places[i];
            return GestureDetector(
              onTap: () => vm.setSearchQuery(pl['title']!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(pl['img']!, fit: BoxFit.cover),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: Text(
                        pl['title']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),

        // Things & Categories
        Text(
          'Categories & Things',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: categories.map((cat) {
            return ActionChip(
              avatar: Icon(cat['icon'] as IconData, size: 18, color: PhotosColors.googleBlue),
              label: Text(cat['title'] as String),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onPressed: () {
                vm.setSelectedTag(cat['tag'] as String);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}
