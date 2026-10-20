import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';
import 'package:myspace/ui/core/widgets/google_photos_logo.dart';
import 'package:myspace/ui/core/widgets/google_account_sheet.dart';
import 'package:myspace/ui/core/widgets/selection_action_bar.dart';
import 'package:myspace/ui/core/widgets/photo_thumbnail.dart';
import 'package:myspace/ui/core/widgets/timeline_header.dart';
import 'package:myspace/ui/features/detail/photo_detail_screen.dart';
import 'package:myspace/ui/features/photos/memories_carousel.dart';

class PhotosView extends StatelessWidget {
  const PhotosView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PhotosViewModel>();
    final isSelectionMode = vm.isSelectionMode;

    return Scaffold(
      appBar: isSelectionMode ? const SelectionAppBar() : null,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Google Photos Top Search & Account Bar
            if (!isSelectionMode)
              SliverToBoxAdapter(
                child: _buildSearchBar(context, vm),
              ),

            // Top Highlights / Stories Reel
            if (!isSelectionMode && vm.searchQuery.isEmpty && vm.selectedCategory == null)
              SliverToBoxAdapter(
                child: MemoriesCarousel(stories: vm.memories),
              ),

            // Category quick filter chips
            if (!isSelectionMode)
              SliverToBoxAdapter(
                child: _buildCategoryChips(vm),
              ),

            // Grouped Timeline Grid
            ..._buildTimelineSlivers(context, vm),

            // Bottom safe area spacer
            const SliverToBoxAdapter(
              child: SizedBox(height: 80),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, PhotosViewModel vm) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final account = vm.userAccount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: isDark ? PhotosColors.darkSurfaceVariant : PhotosColors.lightSurfaceVariant,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            const HomeSpaceLogo(size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => vm.setTabIndex(3), // Navigate to Search tab
                child: Text(
                  'Search photos & memories...',
                  style: TextStyle(
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              ),
            ),

            // Grid density toggle
            IconButton(
              icon: Icon(
                vm.gridDensity == GridDensity.compact
                    ? Icons.grid_view_outlined
                    : (vm.gridDensity == GridDensity.comfortable
                        ? Icons.view_comfy_outlined
                        : Icons.calendar_view_day_outlined),
                size: 20,
              ),
              tooltip: 'Toggle Grid View',
              onPressed: () => vm.cycleGridDensity(),
            ),

            // User Avatar with Sync Badge
            Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: GestureDetector(
                onTap: () => GoogleAccountSheet.show(context),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundImage: account.avatarUrl.isNotEmpty ? NetworkImage(account.avatarUrl) : null,
                      child: account.avatarUrl.isEmpty ? const Icon(Icons.person, size: 16) : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: account.isGuest
                              ? Colors.grey
                              : (account.isBackupEnabled ? PhotosColors.googleGreen : Colors.grey),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? PhotosColors.darkSurfaceVariant : Colors.white,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          account.isGuest
                              ? Icons.cloud_off
                              : (account.isBackupEnabled ? Icons.check : Icons.pause),
                          size: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips(PhotosViewModel vm) {
    final categories = ['All', 'Favorites', 'Videos', 'Motion', 'Mountains', 'Beach', 'City', 'Food'];

    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: categories.length,
        itemBuilder: (ctx, i) {
          final cat = categories[i];
          final isSelected = (cat == 'All' && vm.selectedCategory == null) ||
              (vm.selectedCategory == cat);

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Text(cat),
              selected: isSelected,
              onSelected: (_) {
                if (cat == 'All') {
                  vm.setSelectedCategory(null);
                } else {
                  vm.setSelectedCategory(isSelected ? null : cat);
                }
              },
              showCheckmark: false,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildTimelineSlivers(BuildContext context, PhotosViewModel vm) {
    final grouped = vm.groupedTimelineItems;

    if (grouped.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'No photos found',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => vm.clearAllFilters(),
                  child: const Text('Reset filters'),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final List<Widget> slivers = [];

    grouped.forEach((dateLabel, items) {
      // Header for this date
      slivers.add(
        SliverToBoxAdapter(
          child: TimelineHeader(
            dateTitle: dateLabel,
            items: items,
          ),
        ),
      );

      // Photos Grid for this date
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: vm.crossAxisCount,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 1.0,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                return PhotoThumbnail(
                  item: item,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PhotoDetailScreen(item: item),
                      ),
                    );
                  },
                );
              },
              childCount: items.length,
            ),
          ),
        ),
      );
    });

    return slivers;
  }
}
