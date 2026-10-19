import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/domain/models/album.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/widgets/photo_thumbnail.dart';
import 'package:myspace/ui/features/detail/photo_detail_screen.dart';

class AlbumDetailScreen extends StatelessWidget {
  final Album album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = context.watch<PhotosViewModel>();
    final activeItems = vm.activeItems;
    final albumItems = activeItems.where((i) => album.mediaIds.contains(i.id)).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                album.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    album.coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share album',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sharing "${album.title}" link...')),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                tooltip: 'Add photos',
                onPressed: () => _showAddPhotosPicker(context, vm),
              ),
            ],
          ),

          // Metadata row
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  Text(
                    '${albumItems.length} items',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (album.isShared)
                    Row(
                      children: [
                        const Icon(Icons.people_outline, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        const Text('Shared', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                ],
              ),
            ),
          ),

          // Grid of items
          if (albumItems.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_album_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('No photos in this album yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _showAddPhotosPicker(context, vm),
                      icon: const Icon(Icons.add),
                      label: const Text('Add photos'),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = albumItems[index];
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
                  childCount: albumItems.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAddPhotosPicker(BuildContext context, PhotosViewModel vm) {
    final active = vm.activeItems;
    final Set<String> chosen = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Select photos to add', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    FilledButton(
                      onPressed: () {
                        if (chosen.isNotEmpty) {
                          vm.addSelectedToAlbum(album.id);
                        }
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added ${chosen.length} photos to album')),
                        );
                      },
                      child: Text('Add (${chosen.length})'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    itemCount: active.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 3,
                      mainAxisSpacing: 3,
                    ),
                    itemBuilder: (c, i) {
                      final item = active[i];
                      final isSelected = chosen.contains(item.id);
                      return GestureDetector(
                        onTap: () {
                          setModalState(() {
                            if (isSelected) {
                              chosen.remove(item.id);
                            } else {
                              chosen.add(item.id);
                            }
                          });
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(item.thumbnailUrl, fit: BoxFit.cover),
                            if (isSelected)
                              Container(
                                color: Colors.blue.withValues(alpha: 0.35),
                                child: const Center(
                                  child: Icon(Icons.check_circle, color: Colors.white, size: 28),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
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
