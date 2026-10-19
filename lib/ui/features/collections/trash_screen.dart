import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/domain/models/media_item.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PhotosViewModel>();
    final items = vm.trashItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => _confirmEmptyTrash(context, vm),
              child: const Text('Empty Trash', style: TextStyle(color: PhotosColors.googleRed)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Info Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).cardColor,
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Items backed up to Google Photos will be permanently deleted after 60 days.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Items Grid
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text('Trash is empty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                        onTap: () => _showTrashItemActions(context, vm, item),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              item.thumbnailUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
                            ),
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.restore, color: Colors.white, size: 16),
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

  void _showTrashItemActions(BuildContext context, PhotosViewModel vm, MediaItem item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.restore, color: PhotosColors.googleBlue),
                title: const Text('Restore photo'),
                onTap: () {
                  vm.restoreFromTrash(item.id);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Photo restored to timeline')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: PhotosColors.googleRed),
                title: const Text('Delete permanently'),
                onTap: () {
                  vm.deletePermanently(item.id);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Photo deleted permanently')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmEmptyTrash(BuildContext context, PhotosViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Trash?'),
        content: const Text('All items in the trash will be permanently deleted. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              vm.emptyTrash();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Trash emptied')),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: PhotosColors.googleRed),
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
  }
}
