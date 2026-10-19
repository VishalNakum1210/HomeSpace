import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/features/photos/photos_view.dart';
import 'package:myspace/ui/features/memories/memories_view.dart';
import 'package:myspace/ui/features/collections/collections_view.dart';
import 'package:myspace/ui/features/search/search_view.dart';

class HomeScaffold extends StatelessWidget {
  const HomeScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PhotosViewModel>();
    final isSelectionMode = vm.isSelectionMode;

    final pages = const [
      PhotosView(),
      MemoriesView(),
      CollectionsView(),
      SearchView(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: vm.currentTabIndex,
        children: pages,
      ),
      bottomNavigationBar: isSelectionMode
          ? null
          : NavigationBar(
              selectedIndex: vm.currentTabIndex,
              onDestinationSelected: (index) => vm.setTabIndex(index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.photo_outlined),
                  selectedIcon: Icon(Icons.photo),
                  label: 'Photos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_stories_outlined),
                  selectedIcon: Icon(Icons.auto_stories),
                  label: 'Memories',
                ),
                NavigationDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library),
                  label: 'Collections',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  selectedIcon: Icon(Icons.search),
                  label: 'Search',
                ),
              ],
            ),
    );
  }
}
