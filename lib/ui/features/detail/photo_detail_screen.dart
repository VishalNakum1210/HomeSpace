import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:myspace/domain/models/media_item.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';
import 'package:myspace/ui/features/detail/photo_editor_sheet.dart';
import 'package:myspace/ui/features/detail/google_lens_sheet.dart';

class PhotoDetailScreen extends StatefulWidget {
  final MediaItem item;

  const PhotoDetailScreen({super.key, required this.item});

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  bool _showChrome = true;
  final TransformationController _transformController = TransformationController();

  void _toggleChrome() {
    setState(() {
      _showChrome = !_showChrome;
    });
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PhotosViewModel>();
    final currentItem = vm.getItem(widget.item.id) ?? widget.item;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleChrome,
        onDoubleTap: () {
          if (_transformController.value != Matrix4.identity()) {
            _resetZoom();
          } else {
            _transformController.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Interactive Photo with Adjustments
            Center(
              child: Hero(
                tag: 'media_${currentItem.id}',
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 1.0,
                  maxScale: 5.0,
                  child: _buildAdjustedImage(currentItem),
                ),
              ),
            ),

            // Top Bar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: _showChrome ? 0 : -100,
              left: 0,
              right: 0,
              child: _buildTopBar(context, currentItem, vm),
            ),

            // Bottom Action Bar (Share, Edit, Lens, Delete)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              bottom: _showChrome ? 0 : -100,
              left: 0,
              right: 0,
              child: _buildBottomBar(context, currentItem, vm),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdjustedImage(MediaItem item) {
    Widget img = Image.network(
      item.url,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Image.network(item.thumbnailUrl, fit: BoxFit.contain),
    );

    // Apply filter color matrix or color filter
    if (item.filterName == 'Mono') {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0,    0,    0,    1, 0,
        ]),
        child: img,
      );
    } else if (item.filterName == 'Warm') {
      img = ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.deepOrangeAccent, BlendMode.softLight),
        child: img,
      );
    } else if (item.filterName == 'Cool') {
      img = ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.cyan, BlendMode.softLight),
        child: img,
      );
    } else if (item.filterName == 'Vivid') {
      img = ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.amber, BlendMode.colorBurn),
        child: img,
      );
    }

    return img;
  }

  Widget _buildTopBar(BuildContext context, MediaItem item, PhotosViewModel vm) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        bottom: 12,
        left: 8,
        right: 8,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          if (item.isMotionPhoto)
            IconButton(
              icon: const Icon(Icons.motion_photos_on_outlined, color: Colors.white),
              tooltip: 'Motion Photo',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Playing Motion Photo...')),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.cast, color: Colors.white),
            tooltip: 'Cast to screen',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Searching for Cast devices...')),
              );
            },
          ),
          IconButton(
            icon: Icon(
              item.isFavorite ? Icons.star : Icons.star_border,
              color: item.isFavorite ? Colors.amber : Colors.white,
            ),
            tooltip: 'Favorite',
            onPressed: () => vm.toggleFavorite(item.id),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            tooltip: 'Details',
            onPressed: () => _showExifDetailsSheet(context, item),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (val) {
              if (val == 'archive') {
                vm.toggleArchive(item.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Photo archived')),
                );
              } else if (val == 'lock') {
                vm.moveToLockedFolder(item.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Moved to Locked Folder')),
                );
              } else if (val == 'wallpaper') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Set as wallpaper')),
                );
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'archive',
                child: ListTile(
                  leading: Icon(Icons.archive_outlined),
                  title: Text('Archive'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'lock',
                child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Move to Locked Folder'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'wallpaper',
                child: ListTile(
                  leading: Icon(Icons.wallpaper),
                  title: Text('Use as wallpaper'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, MediaItem item, PhotosViewModel vm) {
    return Container(
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
        left: 16,
        right: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomActionItem(
            icon: Icons.share_outlined,
            label: 'Share',
            onTap: () => _showShareSheet(context, item),
          ),
          _BottomActionItem(
            icon: Icons.tune,
            label: 'Edit',
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => PhotoEditorSheet(item: item),
              );
            },
          ),
          _BottomActionItem(
            icon: Icons.document_scanner_outlined,
            label: 'Lens',
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => GoogleLensSheet(item: item),
              );
            },
          ),
          _BottomActionItem(
            icon: Icons.delete_outline,
            label: 'Delete',
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Move to Trash?'),
                  content: const Text('Items in trash will be permanently deleted after 60 days.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        vm.moveToTrash(item.id);
                        Navigator.pop(context); // Close detail screen
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Item moved to trash')),
                        );
                      },
                      child: const Text('Move to trash'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showShareSheet(BuildContext context, MediaItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share in Google Photos',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // Recent Contacts
              SizedBox(
                height: 90,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _ContactShareAvatar(name: 'Sophia', email: 'sophia@gmail.com', ctx: ctx),
                    _ContactShareAvatar(name: 'Alex', email: 'alex@gmail.com', ctx: ctx),
                    _ContactShareAvatar(name: 'Liam', email: 'liam@gmail.com', ctx: ctx),
                    _ContactShareAvatar(name: 'Emma', email: 'emma@gmail.com', ctx: ctx),
                  ],
                ),
              ),
              const Divider(height: 24),
              // Quick Actions
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: PhotosColors.googleBlue,
                  child: Icon(Icons.link, color: Colors.white),
                ),
                title: const Text('Create link'),
                subtitle: const Text('Anyone with link can view'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied to clipboard: https://photos.app.goo.gl/share')),
                  );
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: PhotosColors.googleGreen,
                  child: Icon(Icons.chat, color: Colors.white),
                ),
                title: const Text('WhatsApp'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Opening WhatsApp...')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExifDetailsSheet(BuildContext context, MediaItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final dateFormatted = DateFormat('EEE, MMM d, yyyy • h:mm a').format(item.dateTime);

        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (_, scrollCtrl) => SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Details',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),

                  // Date & Time
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    title: dateFormatted,
                    subtitle: 'Taken on device',
                  ),

                  // Location
                  _DetailRow(
                    icon: Icons.location_on_outlined,
                    title: item.location,
                    subtitle: '${item.latitude.toStringAsFixed(4)}, ${item.longitude.toStringAsFixed(4)}',
                  ),

                  // Camera
                  _DetailRow(
                    icon: Icons.camera_outlined,
                    title: item.cameraInfo,
                    subtitle: 'Back Camera',
                  ),

                  // Resolution & File size
                  _DetailRow(
                    icon: Icons.photo_outlined,
                    title: item.title,
                    subtitle: '${item.resolution} • ${item.fileSize}',
                  ),

                  // Backup status
                  _DetailRow(
                    icon: Icons.cloud_done_outlined,
                    title: 'Backed up in Original Quality',
                    subtitle: 'Stored in Google Photos cloud',
                    iconColor: PhotosColors.googleGreen,
                  ),

                  // People tagged
                  if (item.people.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'People in this photo',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: item.people.map((p) => Chip(
                        avatar: const CircleAvatar(child: Icon(Icons.person, size: 14)),
                        label: Text(p),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BottomActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactShareAvatar extends StatelessWidget {
  final String name;
  final String email;
  final BuildContext ctx;

  const _ContactShareAvatar({required this.name, required this.email, required this.ctx});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14.0),
      child: InkWell(
        onTap: () {
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sent to $name')),
          );
        },
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: PhotosColors.googleBlue.withValues(alpha: 0.2),
              child: Text(name[0], style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            Text(name, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;

  const _DetailRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: iconColor ?? theme.iconTheme.color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
