import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/domain/models/media_item.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';

class PhotoThumbnail extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;

  const PhotoThumbnail({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PhotosViewModel>();
    final isSelected = vm.selectedIds.contains(item.id);
    final isSelectionMode = vm.isSelectionMode;

    return GestureDetector(
      onTap: () {
        if (isSelectionMode) {
          vm.toggleSelection(item.id);
        } else {
          onTap();
        }
      },
      onLongPress: () {
        vm.toggleSelection(item.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.all(isSelected ? 6.0 : 0.8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isSelected ? 14 : 0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image Thumbnail with Fallback
              Hero(
                tag: 'media_${item.id}',
                child: Image.network(
                  item.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Color(item.dominantColorValue),
                      child: Center(
                        child: Icon(
                          item.isVideo ? Icons.videocam : Icons.photo,
                          color: Colors.white70,
                          size: 32,
                        ),
                      ),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Color(item.dominantColorValue).withValues(alpha: 0.4),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Selected dimming gradient overlay
              if (isSelected)
                Container(
                  color: PhotosColors.googleBlue.withValues(alpha: 0.3),
                ),

              // Top Left: Selection Checkmark Circle (Google Photos style)
              if (isSelectionMode || isSelected)
                Positioned(
                  top: 6,
                  left: 6,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? PhotosColors.googleBlue : Colors.black.withValues(alpha: 0.3),
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),

              // Top Right: Motion Photo indicator
              if (item.isMotionPhoto && !isSelectionMode)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.motion_photos_on_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),

              // Bottom Right: Video duration or Favorite Star
              Positioned(
                bottom: 4,
                right: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.isFavorite && !isSelectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 4.0),
                        child: Icon(
                          Icons.star,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    if (item.isVideo && item.duration != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_arrow, size: 12, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              item.duration!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
