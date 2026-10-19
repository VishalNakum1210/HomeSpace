import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';
import 'package:myspace/ui/features/collections/trash_screen.dart';
import 'package:myspace/ui/features/collections/favorites_screen.dart';
import 'package:myspace/ui/features/collections/archive_screen.dart';
import 'package:myspace/ui/features/collections/locked_folder_screen.dart';
import 'package:myspace/ui/features/collections/album_detail_screen.dart';

class CollectionsView extends StatelessWidget {
  const CollectionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = context.watch<PhotosViewModel>();
    final albums = vm.albums;
    final folders = vm.deviceFolders;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Collections',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          // 4 Main Utility Cards
          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.star_outline,
                  title: 'Favorites',
                  subtitle: '${vm.favoriteItems.length} items',
                  color: PhotosColors.googleYellow,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen()));
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.delete_outline,
                  title: 'Trash',
                  subtitle: '${vm.trashItems.length} items',
                  color: PhotosColors.googleRed,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashScreen()));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.archive_outlined,
                  title: 'Archive',
                  subtitle: '${vm.archivedItems.length} items',
                  color: PhotosColors.googleBlue,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchiveScreen()));
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.lock_outline,
                  title: 'Locked Folder',
                  subtitle: '${vm.lockedItems.length} items',
                  color: PhotosColors.googleGreen,
                  onTap: () {
                    _promptLockedFolder(context, vm);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Albums Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Albums',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () => _showNewAlbumDialog(context, vm),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New album'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Albums Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: albums.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
              childAspectRatio: 0.84,
            ),
            itemBuilder: (context, index) {
              final album = albums[index];
              return _AlbumGridItem(album: album);
            },
          ),
          const SizedBox(height: 28),

          // Photos on this device Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Photos on device',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Viewing all device folders')),
                  );
                },
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Device Folders Horizontal List
          SizedBox(
            height: 160,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: folders.length,
              itemBuilder: (context, index) {
                final folder = folders[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            children: [
                              Image.network(
                                folder.coverUrl,
                                width: 120,
                                height: 110,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 120,
                                  height: 110,
                                  color: Colors.grey,
                                  child: const Icon(Icons.folder, size: 36),
                                ),
                              ),
                              if (folder.isBackedUp)
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.cloud_done, color: Colors.white, size: 14),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          folder.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${folder.itemCount}',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _promptLockedFolder(BuildContext context, PhotosViewModel vm) {
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.lock, color: PhotosColors.googleBlue),
            SizedBox(width: 8),
            Text('Locked Folder'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter device screen lock PIN (Default: 1234)'),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              autofocus: true,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(
                hintText: 'PIN',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final pin = pinController.text.trim();
              if (vm.unlockLockedFolder(pin)) {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LockedFolderScreen()),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incorrect PIN! Try: 1234')),
                );
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  void _showNewAlbumDialog(BuildContext context, PhotosViewModel vm) {
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Album'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Album title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isNotEmpty) {
                vm.createAlbum(title, []);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Album "$title" created')),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? PhotosColors.darkSurfaceVariant : PhotosColors.lightSurfaceVariant,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? PhotosColors.darkBorder : PhotosColors.lightBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumGridItem extends StatelessWidget {
  final dynamic album;

  const _AlbumGridItem({required this.album});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    album.coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
                  ),
                  if (album.isShared)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.people, color: Colors.white, size: 14),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            album.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${album.itemCount} items',
            style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
