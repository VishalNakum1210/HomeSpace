import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';
import 'package:myspace/ui/features/detail/photo_detail_screen.dart';

class LockedFolderScreen extends StatelessWidget {
  const LockedFolderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PhotosViewModel>();
    final items = vm.lockedItems;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.lock, size: 20, color: PhotosColors.googleGreen),
            SizedBox(width: 8),
            Text('Locked Folder'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_reset),
            tooltip: 'Lock now',
            onPressed: () {
              vm.lockLockedFolder();
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.amber.withValues(alpha: 0.12),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: Colors.amber, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Items here are hidden from all apps, cloud backups, and require PIN to view.',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text('Nothing in Locked Folder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: Text(
                            'Select photos from the main timeline or detail view to move them to your private Locked Folder.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
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
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => PhotoDetailScreen(item: item)),
                          );
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              item.thumbnailUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton(
                                icon: const Icon(Icons.lock_open, color: Colors.white, size: 18),
                                tooltip: 'Move out of locked folder',
                                onPressed: () {
                                  vm.removeFromLockedFolder(item.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Moved out of Locked Folder')),
                                  );
                                },
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
    );
  }
}
