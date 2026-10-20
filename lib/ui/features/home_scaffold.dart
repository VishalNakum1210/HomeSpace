import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';
import 'package:myspace/ui/features/photos/photos_view.dart';
import 'package:myspace/ui/features/collections/collections_view.dart';
import 'package:myspace/ui/features/create/create_view.dart';
import 'package:myspace/ui/features/search/search_view.dart';

class HomeScaffold extends StatelessWidget {
  const HomeScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final vm = context.watch<PhotosViewModel>();
    final isSelectionMode = vm.isSelectionMode;

    // Google Photos 7.97 Navigation architecture:
    // Tab 0: Photos
    // Tab 1: Collections (includes Memories & Utility Folders)
    // Tab 2: Create (Creative Studio hub)
    // Tab 3: Search (Gemini Ask Photos + Classic Search)
    final pages = const [
      PhotosView(),
      CollectionsView(),
      CreateView(),
      SearchView(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          // Screen View Stack
          IndexedStack(
            index: vm.currentTabIndex,
            children: pages,
          ),

          // Google Photos 7.97 Signature Floating Navigation Bar & Detached Search Button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                offset: isSelectionMode ? const Offset(0, 1.5) : Offset.zero,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isSelectionMode ? 0.0 : 1.0,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14.0, left: 16.0, right: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Floating Pill Bar: Photos | Collections | Create
                        _buildFloatingPill(context, vm, isDark),
                        const SizedBox(width: 10),
                        // Detached Floating Search / Ask Photos Button
                        _buildFloatingSearchButton(context, vm, isDark),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingPill(BuildContext context, PhotosViewModel vm, bool isDark) {
    final pillBg = isDark ? const Color(0xFF282828) : Colors.white;
    final borderColor = isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: borderColor, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FloatingPillItem(
            index: 0,
            currentIndex: vm.currentTabIndex,
            label: 'Photos',
            selectedIcon: Icons.photo,
            unselectedIcon: Icons.photo_outlined,
            onTap: () => vm.setTabIndex(0),
          ),
          _FloatingPillItem(
            index: 1,
            currentIndex: vm.currentTabIndex,
            label: 'Collections',
            selectedIcon: Icons.photo_library,
            unselectedIcon: Icons.photo_library_outlined,
            onTap: () => vm.setTabIndex(1),
          ),
          _FloatingPillItem(
            index: 2,
            currentIndex: vm.currentTabIndex,
            label: 'Create',
            selectedIcon: Icons.add_circle,
            unselectedIcon: Icons.add_circle_outline,
            onTap: () => vm.setTabIndex(2),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingSearchButton(BuildContext context, PhotosViewModel vm, bool isDark) {
    final isSelected = vm.currentTabIndex == 3;
    final activeBg = isDark ? PhotosColors.googleBlue : PhotosColors.googleBlue;
    final inactiveBg = isDark ? const Color(0xFF282828) : Colors.white;
    final borderColor = isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08);

    return GestureDetector(
      onTap: () => vm.setTabIndex(3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isSelected ? activeBg : inactiveBg,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.transparent : borderColor,
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? PhotosColors.googleBlue.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: isSelected
              ? const Icon(Icons.search, color: Colors.white, size: 24)
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.search,
                      color: isDark ? Colors.white70 : Colors.black87,
                      size: 24,
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Icon(
                        Icons.auto_awesome,
                        color: PhotosColors.googleBlue,
                        size: 10,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _FloatingPillItem extends StatelessWidget {
  final int index;
  final int currentIndex;
  final String label;
  final IconData selectedIcon;
  final IconData unselectedIcon;
  final VoidCallback onTap;

  const _FloatingPillItem({
    required this.index,
    required this.currentIndex,
    required this.label,
    required this.selectedIcon,
    required this.unselectedIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = index == currentIndex;

    final activeIndicatorColor = isDark
        ? const Color(0xFF004A77)
        : const Color(0xFFD3E3FD);
    final activeTextColor = isDark
        ? const Color(0xFFC2E7FF)
        : const Color(0xFF041E49);
    final activeIconColor = isDark
        ? const Color(0xFFC2E7FF)
        : const Color(0xFF041E49);
    final inactiveColor = isDark ? Colors.white70 : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 16 : 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isSelected ? activeIndicatorColor : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? selectedIcon : unselectedIcon,
                color: isSelected ? activeIconColor : inactiveColor,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? activeTextColor : inactiveColor,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
