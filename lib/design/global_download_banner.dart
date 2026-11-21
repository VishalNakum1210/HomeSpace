import 'package:flutter/material.dart';

import '../application/download_service.dart';
import '../application/home_scope.dart';
import '../pages/media_viewer.dart';

class GlobalDownloadBanner extends StatelessWidget {
  const GlobalDownloadBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadService.instance,
      builder: (context, _) {
        final downloads = DownloadService.instance;
        if (!downloads.hasActiveDownload) {
          return const SizedBox.shrink();
        }

        final isCompleted = downloads.phase == DownloadPhase.completed;
        final isFailed = downloads.phase == DownloadPhase.failed;
        final isDownloading = downloads.isDownloading;

        return Material(
          key: const ValueKey('global-download-banner'),
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isCompleted
                  ? const Color(0xF0102A1C)
                  : isFailed
                      ? const Color(0xF02A1010)
                      : const Color(0xF01E2630),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCompleted
                    ? const Color(0xFF4CAF50).withValues(alpha: 0.4)
                    : isFailed
                        ? const Color(0xFFE57373).withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.15),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                final mediaId = downloads.currentMediaId;
                if (mediaId != null) {
                  try {
                    final repository = HomeScope.of(context);
                    final media = repository.mediaById(mediaId);
                    if (media != null) {
                      openMediaViewer(
                        context,
                        mediaIds: [mediaId],
                        initialId: mediaId,
                      );
                    }
                  } catch (_) {}
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? const Color(0xFF4CAF50).withValues(alpha: 0.2)
                              : isFailed
                                  ? const Color(0xFFE57373).withValues(alpha: 0.2)
                                  : const Color(0xFF6366F1).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: isCompleted
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF4CAF50),
                                  size: 20,
                                )
                              : isFailed
                                  ? const Icon(
                                      Icons.error_outline_rounded,
                                      color: Color(0xFFE57373),
                                      size: 20,
                                    )
                                  : const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF818CF8),
                                      ),
                                    ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              downloads.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (downloads.detail.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                downloads.detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCompleted
                                      ? const Color(0xFFA5D6A7)
                                      : isFailed
                                          ? const Color(0xFFEF9A9A)
                                          : const Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.white54,
                        ),
                        tooltip: 'Dismiss',
                        onPressed: downloads.dismiss,
                      ),
                    ],
                  ),
                  if (isDownloading) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        key: const ValueKey('global-download-progress-bar'),
                        value: downloads.progress,
                        minHeight: 4,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF6366F1),
                        ),
                      ),
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
