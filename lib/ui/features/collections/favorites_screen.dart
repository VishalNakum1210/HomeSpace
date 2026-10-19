import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/widgets/photo_thumbnail.dart';
import 'package:myspace/ui/features/detail/photo_detail_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PhotosViewModel>();
    final items = vm.favoriteItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_border, size: 64, color: Colors.amber.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  const Text('No favorites yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the star icon on any photo to add it here',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
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
    );
  }
}
