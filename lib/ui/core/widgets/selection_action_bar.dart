import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';

class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PhotosViewModel>();
    final count = vm.selectedIds.length;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => vm.clearSelection(),
      ),
      title: Text(
        '$count selected',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.share_outlined),
          tooltip: 'Share',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Sharing $count photos...')),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.star_border),
          tooltip: 'Favorite',
          onPressed: () => vm.favoriteSelected(),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Move to Trash?'),
                content: Text('Items in trash will be deleted after 60 days.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      vm.deleteSelected();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Moved $count items to trash')),
                      );
                    },
                    child: const Text('Move to trash'),
                  ),
                ],
              ),
            );
          },
        ),
        PopupMenuButton<String>(
          onSelected: (val) {
            if (val == 'archive') {
              vm.archiveSelected();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Archived $count items')),
              );
            } else if (val == 'locked') {
              for (final id in vm.selectedIds.toList()) {
                vm.moveToLockedFolder(id);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Moved $count items to Locked Folder')),
              );
            } else if (val == 'album') {
              _showAddToAlbumDialog(context, vm);
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'album',
              child: ListTile(
                leading: Icon(Icons.add_photo_alternate_outlined),
                title: Text('Add to album'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'archive',
              child: ListTile(
                leading: Icon(Icons.archive_outlined),
                title: Text('Archive'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'locked',
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Move to Locked Folder'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddToAlbumDialog(BuildContext context, PhotosViewModel vm) {
    final albums = vm.albums;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add to Album'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.add),
                ),
                title: const Text('New album'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreateAlbumDialog(context, vm);
                },
              ),
              const Divider(),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: albums.length,
                  itemBuilder: (c, i) {
                    final album = albums[i];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          album.coverUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 44,
                            height: 44,
                            color: Colors.grey,
                            child: const Icon(Icons.image, size: 20),
                          ),
                        ),
                      ),
                      title: Text(album.title),
                      subtitle: Text('${album.itemCount} items'),
                      onTap: () {
                        vm.addSelectedToAlbum(album.id);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added to ${album.title}')),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showCreateAlbumDialog(BuildContext context, PhotosViewModel vm) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Album'),
        content: TextField(
          controller: textController,
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
              final title = textController.text.trim();
              if (title.isNotEmpty) {
                vm.createAlbum(title, vm.selectedIds.toList());
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created album "$title"')),
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
