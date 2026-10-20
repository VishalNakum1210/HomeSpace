import 'dart:async';
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

class PhotosView extends StatefulWidget {
  const PhotosView({super.key});

  @override
  State<PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<PhotosView> {
  bool _isScrolling = false;
  String _activeScrollDate = 'October 2026';
  Timer? _scrollFadeTimer;

  @override
  void dispose() {
    _scrollFadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final vm = context.watch<PhotosViewModel>();
    final isSelectionMode = vm.isSelectionMode;

    return Scaffold(
      appBar: isSelectionMode ? const SelectionAppBar() : null,
      body: SafeArea(
        child: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                if (scrollInfo is ScrollUpdateNotification) {
                  final grouped = vm.groupedTimelineItems;
                  if (grouped.isNotEmpty) {
                    final keys = grouped.keys.toList();
                    final index = ((scrollInfo.metrics.pixels / 600).floor()).clamp(0, keys.length - 1);
                    final dateKey = keys[index];
                    if (_activeScrollDate != dateKey) {
                      setState(() => _activeScrollDate = dateKey);
                    }
                  }

                  if (!_isScrolling) {
                    setState(() => _isScrolling = true);
                  }
                  _scrollFadeTimer?.cancel();
                  _scrollFadeTimer = Timer(const Duration(milliseconds: 1200), () {
                    if (mounted) {
                      setState(() => _isScrolling = false);
                    }
                  });
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  // Google Photos Search & Account Top Bar
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

                  // Bottom spacer for navigation bar clearance
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 80),
                  ),
                ],
              ),
            ),

            // Dynamic Floating Date Indicator Capsule during Scroll
            if (!isSelectionMode)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                top: _isScrolling ? 12 : -50,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isScrolling ? 1.0 : 0.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF2E2E2E) : Colors.black87),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today, size: 13, color: Colors.white70),
                          const SizedBox(width: 8),
                          Text(
                            _activeScrollDate,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
