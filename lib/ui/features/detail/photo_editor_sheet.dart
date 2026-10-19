import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/domain/models/media_item.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';

class PhotoEditorSheet extends StatefulWidget {
  final MediaItem item;

  const PhotoEditorSheet({super.key, required this.item});

  @override
  State<PhotoEditorSheet> createState() => _PhotoEditorSheetState();
}

class _PhotoEditorSheetState extends State<PhotoEditorSheet> {
  int _selectedTab = 0; // 0: Suggestions, 1: Crop, 2: Adjust
  late String _currentFilter;
  late double _brightness;
  late double _contrast;
  late double _saturation;

  final List<String> _filters = ['Original', 'Enhance', 'Warm', 'Cool', 'Vivid', 'Mono'];

  @override
  void initState() {
    super.initState();
    _currentFilter = widget.item.filterName;
    _brightness = widget.item.brightnessAdjustment;
    _contrast = widget.item.contrastAdjustment;
    _saturation = widget.item.saturationAdjustment;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<PhotosViewModel>();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF1F1F1F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top Bar: Cancel & Save
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                  ),
                  const Text(
                    'Editor',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  FilledButton(
                    onPressed: () {
                      vm.updatePhotoAdjustments(
                        id: widget.item.id,
                        brightness: _brightness,
                        contrast: _contrast,
                        saturation: _saturation,
                        filterName: _currentFilter,
                      );
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Edits saved successfully!')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: PhotosColors.googleBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: const Text('Save copy'),
                  ),
                ],
              ),
            ),

            // Live Image Preview in Editor
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildFilteredPreview(),
                  ),
                ),
              ),
            ),

            // Editor Controls Area
            Container(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              color: const Color(0xFF141414),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Tab content
                  if (_selectedTab == 0) _buildSuggestions(),
                  if (_selectedTab == 1) _buildCropOptions(),
                  if (_selectedTab == 2) _buildAdjustSliders(),

                  const SizedBox(height: 12),
                  // Bottom Tab Selector (Suggestions / Crop / Adjust)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildEditorTabItem(0, 'Suggestions', Icons.auto_awesome),
                      _buildEditorTabItem(1, 'Crop', Icons.crop),
                      _buildEditorTabItem(2, 'Adjust', Icons.tune),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteredPreview() {
    Widget img = Image.network(
      widget.item.url,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Image.network(widget.item.thumbnailUrl, fit: BoxFit.contain),
    );

    if (_currentFilter == 'Mono') {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0,    0,    0,    1, 0,
        ]),
        child: img,
      );
    } else if (_currentFilter == 'Warm') {
      img = ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.deepOrangeAccent, BlendMode.softLight),
        child: img,
      );
    } else if (_currentFilter == 'Cool') {
      img = ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.cyan, BlendMode.softLight),
        child: img,
      );
    } else if (_currentFilter == 'Vivid') {
      img = ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.amber, BlendMode.colorBurn),
        child: img,
      );
    } else if (_currentFilter == 'Enhance') {
      img = ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.white30, BlendMode.overlay),
        child: img,
      );
    }

    return img;
  }

  Widget _buildSuggestions() {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        itemBuilder: (ctx, i) {
          final filter = _filters[i];
          final isSelected = _currentFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: InkWell(
              onTap: () {
                setState(() => _currentFilter = filter);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 70,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? PhotosColors.googleBlue : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          widget.item.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      filter,
                      style: TextStyle(
                        color: isSelected ? PhotosColors.googleBlue : Colors.white70,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCropOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.rotate_right, color: Colors.white),
            tooltip: 'Rotate 90°',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Rotated 90° clockwise')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.crop_free, color: Colors.white),
            tooltip: 'Freeform',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.crop_square, color: Colors.white),
            tooltip: '1:1 Square',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.crop_16_9, color: Colors.white),
            tooltip: '16:9 Landscape',
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustSliders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.brightness_6, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Text('Brightness', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _brightness,
                  min: -0.5,
                  max: 0.5,
                  onChanged: (val) => setState(() => _brightness = val),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.contrast, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Text('Contrast', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _contrast,
                  min: 0.5,
                  max: 1.5,
                  onChanged: (val) => setState(() => _contrast = val),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditorTabItem(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: ChoiceChip(
        avatar: Icon(
          icon,
          size: 16,
          color: isSelected ? PhotosColors.googleBlue : Colors.white70,
        ),
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedTab = index),
        selectedColor: PhotosColors.googleBlue.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: isSelected ? PhotosColors.googleBlue : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
