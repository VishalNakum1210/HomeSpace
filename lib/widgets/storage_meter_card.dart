import 'package:flutter/material.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../services/cache_service.dart';

class StorageMeterCard extends StatefulWidget {
  final HomeRepository repository;
  const StorageMeterCard({super.key, required this.repository});

  @override
  State<StorageMeterCard> createState() => _StorageMeterCardState();
}

class _StorageMeterCardState extends State<StorageMeterCard> {
  StorageBreakdown? _stats;
  int _cacheBytes = 0;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await widget.repository.getStorageBreakdown();
      final cache = await CacheService.getCacheSizeBytes();
      if (mounted) {
        setState(() {
          _stats = stats;
          _cacheBytes = cache;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleClearCache() async {
    setState(() => _clearingCache = true);
    final reclaimed = await CacheService.clearCache();
    final updatedCache = await CacheService.getCacheSizeBytes();
    if (mounted) {
      setState(() {
        _cacheBytes = updatedCache;
        _clearingCache = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            reclaimed > 0
                ? 'App cache cleared. Reclaimed ${CacheService.formatBytes(reclaimed)}.'
                : 'App cache is clean.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final stats = _stats ??
        const StorageBreakdown(
          photosBytes: 0,
          videosBytes: 0,
          totalUsedBytes: 0,
          quotaBytes: 15 * 1024 * 1024 * 1024,
        );

    final totalUsedStr = StorageBreakdown.formatBytes(stats.totalUsedBytes);
    final quotaStr = StorageBreakdown.formatBytes(stats.quotaBytes);

    const photosColor = Color(0xFF1A73E8); // Google blue
    const videosColor = Color(0xFF8E24AA); // Purple
    final freeColor = dark ? Colors.grey.shade800 : const Color(0xFFE0E0E0);

    final photosRatio = stats.photosRatio;
    final videosRatio = stats.videosRatio;
    final freeRatio = (1.0 - photosRatio - videosRatio).clamp(0.0, 1.0);

    return SpaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, color: style.accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Storage & Space',
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$totalUsedStr of $quotaStr used',
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          // Google Photos style segmented visual progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  if (photosRatio > 0)
                    Flexible(
                      flex: (photosRatio * 1000).toInt().clamp(1, 1000),
                      child: Container(color: photosColor),
                    ),
                  if (videosRatio > 0)
                    Flexible(
                      flex: (videosRatio * 1000).toInt().clamp(1, 1000),
                      child: Container(color: videosColor),
                    ),
                  Flexible(
                    flex: (freeRatio * 1000).toInt().clamp(1, 1000),
                    child: Container(color: freeColor),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 8,
            children: [
              _LegendItem(
                color: photosColor,
                label: 'Photos',
                value: StorageBreakdown.formatBytes(stats.photosBytes),
              ),
              _LegendItem(
                color: videosColor,
                label: 'Videos',
                value: StorageBreakdown.formatBytes(stats.videosBytes),
              ),
              _LegendItem(
                color: dark ? Colors.grey.shade400 : Colors.grey.shade600,
                label: 'Free',
                value: StorageBreakdown.formatBytes(stats.freeBytes),
              ),
            ],
          ),
          const Divider(height: 24),
          // Cache management row
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cached_rounded, color: dark ? Colors.grey.shade300 : const Color(0xFF424242), size: 20),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'App Cache',
                        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _cacheBytes > 0
                            ? '${CacheService.formatBytes(_cacheBytes)} of temporary previews'
                            : 'Cache is clean (0 B)',
                        style: text.bodySmall?.copyWith(
                          color: dark ? Colors.grey.shade300 : const Color(0xFF424242),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              OutlinedButton(
                key: const ValueKey('clear-cache-btn'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(88, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _clearingCache ? null : _handleClearCache,
                child: Text(_clearingCache ? 'Clearing…' : 'Clear Cache'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: text.bodySmall?.copyWith(
                fontSize: 12,
                color: dark ? Colors.grey.shade200 : const Color(0xFF212121),
              ),
            ),
            Text(
              value,
              style: text.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: dark ? Colors.white : const Color(0xFF212121),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
