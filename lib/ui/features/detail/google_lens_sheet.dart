import 'package:flutter/material.dart';
import 'package:myspace/domain/models/media_item.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';

class GoogleLensSheet extends StatefulWidget {
  final MediaItem item;

  const GoogleLensSheet({super.key, required this.item});

  @override
  State<GoogleLensSheet> createState() => _GoogleLensSheetState();
}

class _GoogleLensSheetState extends State<GoogleLensSheet> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  int _activeLensTab = 0; // 0: Search, 1: Text, 2: Translate

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top Lens Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: PhotosColors.googleBlue.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.document_scanner, color: PhotosColors.googleBlue, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Google Lens',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Lens Viewfinder with Bounding Box Overlay
            SizedBox(
              height: 200,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      widget.item.thumbnailUrl,
                      height: 200,
                      width: MediaQuery.of(context).size.width - 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        height: 200,
                        width: MediaQuery.of(context).size.width - 32,
                        color: Colors.grey[900],
                        child: const Center(
                          child: Icon(Icons.document_scanner_outlined, color: Colors.white54, size: 48),
                        ),
                      ),
                    ),
                  ),

                  // Animated Scanning Pin / Bounding Box
                  AnimatedBuilder(
                    animation: _animController,
                    builder: (context, _) {
                      return Container(
                        width: 140 + (_animController.value * 12),
                        height: 100 + (_animController.value * 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.85),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: PhotosColors.googleBlue.withValues(alpha: 0.35 * _animController.value),
                              blurRadius: 16,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            margin: const EdgeInsets.all(6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Subject',
                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Lens Mode Chips (Search, Text, Translate)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildModeChip(0, 'Search', Icons.search),
                _buildModeChip(1, 'Text', Icons.text_fields),
                _buildModeChip(2, 'Translate', Icons.translate),
              ],
            ),
            const Divider(height: 24),

            // Visual Match Results
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Text(
                    'Visual matches for "${widget.item.location.split(',').first}"',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildMatchCard(
                    title: widget.item.location,
                    subtitle: 'Popular destination • 4.8 ★ (12,480 reviews)',
                    imageUrl: widget.item.thumbnailUrl,
                  ),
                  const SizedBox(height: 10),
                  _buildMatchCard(
                    title: 'Similar photography & locations',
                    subtitle: 'High dynamic range landscape photography',
                    imageUrl: 'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=300&q=80',
                  ),
                  const SizedBox(height: 10),
                  _buildMatchCard(
                    title: 'Google Maps Explore',
                    subtitle: 'View 360° panorama & reviews near coordinates',
                    imageUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=300&q=80',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip(int index, String label, IconData icon) {
    final isSelected = _activeLensTab == index;
    return ChoiceChip(
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : null),
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _activeLensTab = index),
      selectedColor: PhotosColors.googleBlue,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildMatchCard({
    required String title,
    required String subtitle,
    required String imageUrl,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              imageUrl,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(width: 70, height: 70, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        ],
      ),
    );
  }
}
