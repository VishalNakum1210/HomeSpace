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

  final List<String> _geminiPrompts = [
    'Show photos of me in Tokyo',
    'Delicious meals and dining',
    'Sunset over the mountains',
    'Find documents and notes',
    'Best scenic nature shots',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
            color: isDark ? PhotosColors.darkSurfaceVariant : PhotosColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(24),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => vm.setSearchQuery(val),
            decoration: InputDecoration(
              hintText: vm.searchMode == SearchMode.askPhotos
                  ? 'Ask Photos anything...'
                  : 'Search people, places, things...',
              prefixIcon: Icon(
                vm.searchMode == SearchMode.askPhotos
                    ? Icons.auto_awesome
                    : Icons.search,
                color: vm.searchMode == SearchMode.askPhotos ? PhotosColors.googleBlue : null,
                size: 22,
              ),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0, left: 16.0, right: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildModeTab(
                  label: 'Ask Photos',
                  icon: Icons.auto_awesome,
                  isSelected: vm.searchMode == SearchMode.askPhotos,
                  onTap: () => vm.setSearchMode(SearchMode.askPhotos),
                ),
                const SizedBox(width: 8),
                _buildModeTab(
                  label: 'Classic search',
                  icon: Icons.search,
                  isSelected: vm.searchMode == SearchMode.classic,
                  onTap: () => vm.setSearchMode(SearchMode.classic),
                ),
              ],
            ),
          ),
        ),
      ),
      body: isSearching
          ? _buildSearchResults(context, vm, results)
          : (vm.searchMode == SearchMode.askPhotos
              ? _buildAskPhotosPrompts(context, vm)
              : _buildExploreCategories(context, vm)),
    );
  }

  Widget _buildModeTab({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF004A77) : const Color(0xFFD3E3FD))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : (isDark ? Colors.white24 : Colors.black12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? PhotosColors.googleBlue : null,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? (isDark ? const Color(0xFFC2E7FF) : const Color(0xFF041E49))
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAskPhotosPrompts(BuildContext context, PhotosViewModel vm) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      children: [
        // Gemini Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF132238), const Color(0xFF1C1C1C)]
                  : [const Color(0xFFEBF2FD), const Color(0xFFF8F9FA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: PhotosColors.googleBlue.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: PhotosColors.googleBlue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome, color: PhotosColors.googleBlue, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask Photos with Gemini',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Search naturally like you speak. Try asking for specific moments, themes, or details in your photos.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        Text(
          'Try asking...',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        ..._geminiPrompts.map((prompt) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: InkWell(
              onTap: () {
                _searchController.text = prompt;
                // Parse key terms for smart filtering
                if (prompt.contains('Tokyo')) {
                  vm.setSearchQuery('Tokyo');
                } else if (prompt.contains('meals') || prompt.contains('dining')) {
                  vm.setSelectedTag('Food');
                } else if (prompt.contains('Sunset') || prompt.contains('mountains')) {
                  vm.setSelectedTag('Sunset');
                } else if (prompt.contains('nature') || prompt.contains('scenic')) {
                  vm.setSelectedTag('Nature');
                } else {
                  vm.setSearchQuery(prompt);
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? PhotosColors.darkSurfaceVariant : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? PhotosColors.darkBorder : PhotosColors.lightBorder,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: PhotosColors.googleBlue, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        prompt,
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[500]),
                  ],
                ),
              ),
            ),
          );
        }),

        const SizedBox(height: 24),
        Text(
          'Recent People',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _personAvatar('Sophia', 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=150&q=80', vm),
              _personAvatar('Alex', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=150&q=80', vm),
              _personAvatar('Liam', 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=150&q=80', vm),
              _personAvatar('Elena', 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=150&q=80', vm),
            ],
          ),
        ),

        const SizedBox(height: 96), // Clearance for floating navigation pill
      ],
    );
  }

  Widget _personAvatar(String name, String url, PhotosViewModel vm) {
    return Padding(
      padding: const EdgeInsets.only(right: 14.0),
      child: GestureDetector(
        onTap: () => vm.setSelectedPerson(name),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: NetworkImage(url),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context, PhotosViewModel vm, dynamic results) {
    final isGemini = vm.searchMode == SearchMode.askPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gemini Explanation or Active Filter Banner
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isGemini)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: PhotosColors.googleBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PhotosColors.googleBlue.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: PhotosColors.googleBlue, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Gemini found ${results.length} photos matching your request',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${results.length} results',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
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
          height: 112,
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
                    Image.network(
                      pl['img']!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.grey[800],
                        child: const Center(child: Icon(Icons.location_on, color: Colors.white54)),
                      ),
                    ),
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
        const SizedBox(height: 96), // Clearance for floating navigation pill
      ],
    );
  }
}
