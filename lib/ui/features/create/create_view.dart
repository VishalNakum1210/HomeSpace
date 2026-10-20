import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';
import 'package:myspace/domain/models/media_item.dart';
import 'package:myspace/ui/features/memories/story_viewer_screen.dart';

class CreateView extends StatelessWidget {
  const CreateView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final vm = context.watch<PhotosViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Create',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          Text(
            'Bring your memories to life with creative tools and AI',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 20),

          // Primary Creation Tools Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.15,
            children: [
              _CreateToolCard(
                icon: Icons.photo_album_outlined,
                color: PhotosColors.googleBlue,
                title: 'Album',
                subtitle: 'Organize and share with friends',
                onTap: () => _openCreateAlbumDialog(context, vm),
              ),
              _CreateToolCard(
                icon: Icons.auto_awesome_mosaic_outlined,
                color: PhotosColors.googleYellow,
                title: 'Collage',
                subtitle: 'Combine up to 6 photos in artistic layouts',
                onTap: () => _openCollageMaker(context, vm),
              ),
              _CreateToolCard(
                icon: Icons.movie_creation_outlined,
                color: PhotosColors.googleRed,
                title: 'Highlight video',
                subtitle: 'Curated clips set to music',
                onTap: () => _openHighlightVideoPicker(context, vm),
              ),
              _CreateToolCard(
                icon: Icons.motion_photos_on_outlined,
                color: PhotosColors.googleGreen,
                title: 'Cinematic photo',
                subtitle: 'Add 3D depth and parallax motion',
                onTap: () => _openCinematicPhotoPicker(context, vm),
              ),
              _CreateToolCard(
                icon: Icons.gif_box_outlined,
                color: Colors.purple,
                title: 'Animation',
                subtitle: 'Looping motion from similar shots',
                onTap: () => _openAnimationPicker(context, vm),
              ),
              _CreateToolCard(
                icon: Icons.menu_book_outlined,
                color: Colors.teal,
                title: 'Photo book',
                subtitle: 'Premium printed photo albums',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Photo book print services coming soon!')),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 28),

          // Featured AI Creation Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E2638), const Color(0xFF1B1B1B)]
                    : [const Color(0xFFE8F0FE), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: PhotosColors.googleBlue.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PhotosColors.googleBlue.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, color: PhotosColors.googleBlue, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Magic Studio',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Turn your photos into stylized paintings, sketches, and cinematic moments.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Text(
            'Your Albums',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // User Albums horizontal preview
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: vm.albums.length,
              itemBuilder: (context, index) {
                final album = vm.albums[index];
                return Container(
                  width: 130,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          album.coverUrl,
                          height: 90,
                          width: 130,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            height: 90,
                            color: Colors.grey[800],
                            child: const Center(child: Icon(Icons.image, color: Colors.white54)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        '${album.itemCount} items',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 96), // Clearance for floating navigation pill
        ],
      ),
    );
  }

  void _openCreateAlbumDialog(BuildContext context, PhotosViewModel vm) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Album'),
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
                vm.createAlbum(title, []);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Album "$title" created!')),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _openCollageMaker(BuildContext context, PhotosViewModel vm) {
    final items = vm.activeItems.take(6).toList();
    if (items.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CollageMakerModal(items: items),
    );
  }

  void _openHighlightVideoPicker(BuildContext context, PhotosViewModel vm) {
    if (vm.memories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No memories available to create highlight video')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(story: vm.memories.first),
      ),
    );
  }

  void _openCinematicPhotoPicker(BuildContext context, PhotosViewModel vm) {
    final items = vm.activeItems;
    if (items.isEmpty) return;
    final item = items.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CinematicPhotoModal(item: item),
    );
  }

  void _openAnimationPicker(BuildContext context, PhotosViewModel vm) {
    final items = vm.activeItems.take(4).toList();
    if (items.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AnimationBurstModal(items: items),
    );
  }
}

class _CreateToolCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CreateToolCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? PhotosColors.darkSurfaceVariant : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? PhotosColors.darkBorder : PhotosColors.lightBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CollageMakerModal extends StatefulWidget {
  final List<MediaItem> items;

  const _CollageMakerModal({required this.items});

  @override
  State<_CollageMakerModal> createState() => _CollageMakerModalState();
}

class _CollageMakerModalState extends State<_CollageMakerModal> {
  int _selectedLayout = 0; // 0: 2x2 Grid, 1: 1 Big + 2 Small, 2: 3 Strips

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayItems = widget.items.take(4).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text('Collage Studio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Collage saved to library!')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: PhotosColors.googleBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Collage Preview Area
            Expanded(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: _buildCollageLayout(displayItems),
                    ),
                  ),
                ),
              ),
            ),

            // Layout Picker
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _layoutChip(0, 'Grid 2x2', Icons.grid_view),
                  const SizedBox(width: 8),
                  _layoutChip(1, 'Featured + 2', Icons.view_sidebar),
                  const SizedBox(width: 8),
                  _layoutChip(2, 'Strips', Icons.view_column),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layoutChip(int index, String label, IconData icon) {
    final isSelected = _selectedLayout == index;
    return ChoiceChip(
      avatar: Icon(icon, size: 16, color: isSelected ? PhotosColors.googleBlue : null),
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedLayout = index),
      selectedColor: PhotosColors.googleBlue.withValues(alpha: 0.15),
    );
  }

  Widget _buildCollageLayout(List<MediaItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    if (_selectedLayout == 0) {
      // 2x2 Grid
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemCount: math.min(4, items.length),
        itemBuilder: (ctx, i) => Image.network(
          items[i].thumbnailUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
        ),
      );
    } else if (_selectedLayout == 1) {
      // 1 Big Left, 2 Small Right
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: Image.network(
              items[0].thumbnailUrl,
              fit: BoxFit.cover,
              height: double.infinity,
              errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(
                  child: Image.network(
                    items.length > 1 ? items[1].thumbnailUrl : items[0].thumbnailUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: Image.network(
                    items.length > 2 ? items[2].thumbnailUrl : items[0].thumbnailUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      // Vertical Strips
      return Row(
        children: List.generate(
          math.min(3, items.length),
          (i) => Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 2 ? 3 : 0),
              child: Image.network(
                items[i].thumbnailUrl,
                fit: BoxFit.cover,
                height: double.infinity,
                errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
              ),
            ),
          ),
        ),
      );
    }
  }
}

class _CinematicPhotoModal extends StatefulWidget {
  final MediaItem item;

  const _CinematicPhotoModal({required this.item});

  @override
  State<_CinematicPhotoModal> createState() => _CinematicPhotoModalState();
}

class _CinematicPhotoModalState extends State<_CinematicPhotoModal> with SingleTickerProviderStateMixin {
  double _tiltX = 0.0;
  double _tiltY = 0.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text('Cinematic 3D Photo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cinematic video saved to library!')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: PhotosColors.googleGreen,
                    ),
                    child: const Text('Save video'),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),

            Expanded(
              child: Center(
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _tiltX += details.delta.dy * 0.003;
                      _tiltY -= details.delta.dx * 0.003;
                      _tiltX = _tiltX.clamp(-0.25, 0.25);
                      _tiltY = _tiltY.clamp(-0.25, 0.25);
                    });
                  },
                  child: Transform(
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001) // perspective
                      ..rotateX(_tiltX)
                      ..rotateY(_tiltY),
                    alignment: FractionalOffset.center,
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: PhotosColors.googleGreen.withValues(alpha: 0.3),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.network(
                          widget.item.url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Image.network(
                            widget.item.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.touch_app, color: Colors.white70, size: 18),
                  SizedBox(width: 8),
                  Text('Drag to tilt in 3D parallax space', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimationBurstModal extends StatefulWidget {
  final List<MediaItem> items;

  const _AnimationBurstModal({required this.items});

  @override
  State<_AnimationBurstModal> createState() => _AnimationBurstModalState();
}

class _AnimationBurstModalState extends State<_AnimationBurstModal> {
  int _currentIndex = 0;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    _startAnimationLoop();
  }

  void _startAnimationLoop() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) break;
      if (_isPlaying) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % widget.items.length;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.items[_currentIndex];

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text('Looping Animation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Looping GIF saved to library!')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.purple,
                    ),
                    child: const Text('Save GIF'),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),

            Expanded(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      currentItem.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
                    ),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle, color: Colors.white, size: 36),
                    onPressed: () => setState(() => _isPlaying = !_isPlaying),
                  ),
                  const SizedBox(width: 8),
                  Text('Frame ${_currentIndex + 1} of ${widget.items.length}', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
