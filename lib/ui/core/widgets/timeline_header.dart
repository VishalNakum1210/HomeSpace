import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myspace/domain/models/media_item.dart';
import 'package:myspace/ui/view_models/photos_view_model.dart';
import 'package:myspace/ui/core/theme/photos_theme.dart';

class TimelineHeader extends StatelessWidget {
  final String dateTitle;
  final List<MediaItem> items;

  const TimelineHeader({
    super.key,
    required this.dateTitle,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = context.watch<PhotosViewModel>();
    final itemIds = items.map((i) => i.id).toList();
    final allSelected = itemIds.isNotEmpty && itemIds.every((id) => vm.selectedIds.contains(id));
    final someSelected = itemIds.any((id) => vm.selectedIds.contains(id));

    // Derive location snippet from first item
    final locationSnippet = items.isNotEmpty ? items.first.location.split(',').first : '';

    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 8.0, left: 14.0, right: 14.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                if (locationSnippet.isNotEmpty && (dateTitle == 'Today' || dateTitle == 'Yesterday'))
                  Text(
                    locationSnippet,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.65),
                    ),
                  ),
              ],
            ),
          ),

          // Google Photos day-selection checkmark circle
          InkWell(
            onTap: () => vm.selectDayGroup(itemIds),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: allSelected
                    ? PhotosColors.googleBlue
                    : (someSelected ? PhotosColors.googleBlue.withValues(alpha: 0.3) : Colors.transparent),
                border: Border.all(
                  color: allSelected || someSelected
                      ? PhotosColors.googleBlue
                      : theme.dividerColor.withValues(alpha: 0.5),
                  width: 1.8,
                ),
              ),
              child: allSelected
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : (someSelected
                      ? const Icon(Icons.remove, size: 16, color: Colors.white)
                      : null),
            ),
          ),
        ],
      ),
    );
  }
}
