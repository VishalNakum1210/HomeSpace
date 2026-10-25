import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../design/state_artwork.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import 'library_widgets.dart';

enum QueueFilter { all, active, finished }

bool activeUpload(UploadItem item) =>
    ![UploadPhase.completed, UploadPhase.canceled].contains(item.phase);

String uploadLabel(UploadPhase phase) => switch (phase) {
  UploadPhase.queued => 'Queued',
  UploadPhase.uploading => 'In progress',
  UploadPhase.paused => 'Paused',
  UploadPhase.failed => 'Needs retry',
  UploadPhase.completed => 'Completed',
  UploadPhase.canceled => 'Canceled',
};

class UploadsPage extends StatefulWidget {
  const UploadsPage({super.key});
  @override
  State<UploadsPage> createState() => _UploadsPageState();
}

class _UploadsPageState extends State<UploadsPage> {
  QueueFilter filter = QueueFilter.all;

  @override
  Widget build(BuildContext context) => Theme(
    data: spaceTheme(Theme.of(context).brightness, SpacePage.photos),
    child: Builder(
      builder: (context) {
        final repository = HomeScope.of(context);
        final queue = repository.uploads;
        return ListenableBuilder(
          listenable: queue,
          builder: (context, _) {
            final items = queue.items;
            final completed = items
                .where((item) => item.phase == UploadPhase.completed)
                .length;
            final visible = items
                .where(
                  (item) => switch (filter) {
                    QueueFilter.all => true,
                    QueueFilter.active => activeUpload(item),
                    QueueFilter.finished => !activeUpload(item),
                  },
                )
                .toList();
            final text = Theme.of(context).textTheme;
            return Scaffold(
              appBar: AppBar(
                title: const Text('Upload queue'),
                centerTitle: true,
              ),
              body: SafeArea(
                top: false,
                child: CustomScrollView(
                  key: const PageStorageKey('uploads-scroll'),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SpaceCard(
                              color: SpaceStyle.of(context).accentSoft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.cloud_upload_outlined,
                                    size: 36,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'A little closer to home',
                                    style: text.titleLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$completed of ${items.length} sample items completed',
                                    key: const ValueKey('queue-summary'),
                                    style: text.bodyLarge,
                                  ),
                                  const SizedBox(height: 14),
                                  LinearProgressIndicator(
                                    value: items.isEmpty
                                        ? 0
                                        : completed / items.length,
                                    semanticsLabel: 'Completed sample items',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            const MemoryStatusBanner(
                              message: 'Sample queue only. Controls change this session’s demo items. No files are uploaded or imported.',
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final option in QueueFilter.values)
                                  ChoiceChip(
                                    key: ValueKey('queue-${option.name}'),
                                    label: Text(switch (option) {
                                      QueueFilter.all => 'All',
                                      QueueFilter.active => 'Active',
                                      QueueFilter.finished => 'Finished',
                                    }),
                                    selected: filter == option,
                                    onSelected: (_) =>
                                        setState(() => filter = option),
                                  ),
                              ],
                            ),
                            if (filter != QueueFilter.finished &&
                                items.any(activeUpload)) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (items.any(
                                    (item) => [
                                      UploadPhase.queued,
                                      UploadPhase.uploading,
                                    ].contains(item.phase),
                                  ))
                                    TextButton.icon(
                                      key: const ValueKey('pause-all'),
                                      icon: const Icon(Icons.pause_rounded),
                                      label: const Text('Pause all'),
                                      onPressed: () => _batch(
                                        context,
                                        queue,
                                        items,
                                        UploadPhase.uploading,
                                      ),
                                    ),
                                  if (items.any(
                                    (item) => item.phase == UploadPhase.paused,
                                  ))
                                    TextButton.icon(
                                      key: const ValueKey('resume-all'),
                                      icon: const Icon(
                                        Icons.play_arrow_rounded,
                                      ),
                                      label: const Text('Resume all'),
                                      onPressed: () => _batch(
                                        context,
                                        queue,
                                        items,
                                        UploadPhase.paused,
                                      ),
                                    ),
                                  if (items.any(
                                    (item) => item.phase == UploadPhase.failed,
                                  ))
                                    TextButton.icon(
                                      key: const ValueKey('retry-failed'),
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('Retry failed'),
                                      onPressed: () => _batch(
                                        context,
                                        queue,
                                        items,
                                        UploadPhase.failed,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (visible.isEmpty)
                      SliverToBoxAdapter(
                        child: SpaceEmpty(
                          icon: Icons.cloud_done_outlined,
                          title: items.isEmpty
                              ? 'Room for new memories'
                              : filter == QueueFilter.active
                              ? 'All quiet here'
                              : 'Still making memories',
                          message: items.isEmpty
                              ? 'There are no sample uploads in this preview. Your saved library is kept.'
                              : filter == QueueFilter.active
                              ? 'No active sample items. Find completed and canceled items in Finished.'
                              : 'Completed and canceled sample items will appear here.',
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final item = visible[index];
                          // Queue entries may outlive a deleted/trashed library item.
                          final media = repository.media
                              .where((media) => media.id == item.mediaId)
                              .firstOrNull;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _UploadCard(
                              item: item,
                              media: media,
                              queue: queue,
                            ),
                          );
                        },
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 28)),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );

  void _batch(
    BuildContext context,
    UploadRepository queue,
    List<UploadItem> items,
    UploadPhase phase,
  ) {
    _queueAction(context, () {
      for (final item in items) {
        if (phase == UploadPhase.uploading &&
            [UploadPhase.uploading, UploadPhase.queued].contains(item.phase)) {
          queue.pause(item.id);
        } else if (phase == UploadPhase.paused && item.phase == phase) {
          queue.resume(item.id);
        } else if (phase == UploadPhase.failed && item.phase == phase) {
          queue.retry(item.id);
        }
      }
    });
  }
}

void _queueAction(BuildContext context, VoidCallback action) {
  try {
    action();
  } on LocalActionException catch (failure) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

class _UploadCard extends StatelessWidget {
  final UploadItem item;
  final MediaItem? media;
  final UploadRepository queue;
  const _UploadCard({
    required this.item,
    required this.media,
    required this.queue,
  });
  @override
  Widget build(BuildContext context) {
    final title = media?.title ?? 'Unavailable memory';
    final text = Theme.of(context).textTheme;
    final active = activeUpload(item);
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: media == null
                        ? const Icon(Icons.photo_outlined)
                        : MediaThumbnail(media: media!),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      uploadLabel(item.phase),
                      key: ValueKey('upload-state-${item.id}'),
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: item.progress.clamp(0, 1),
              semanticsLabel: '$title sample progress',
            ),
            const SizedBox(height: 6),
            Text(
              '${(item.progress * 100).round()}% · sample progress',
              style: text.bodyMedium,
            ),
          ],
          if (active) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  key: ValueKey('upload-action-${item.id}'),
                  icon: Icon(switch (item.phase) {
                    UploadPhase.failed => Icons.refresh_rounded,
                    UploadPhase.paused => Icons.play_arrow_rounded,
                    _ => Icons.pause_rounded,
                  }),
                  label: Text(switch (item.phase) {
                    UploadPhase.failed => 'Retry',
                    UploadPhase.paused => 'Resume',
                    _ => 'Pause',
                  }),
                  onPressed: () => _queueAction(
                    context,
                    () => switch (item.phase) {
                      UploadPhase.failed => queue.retry(item.id),
                      UploadPhase.paused => queue.resume(item.id),
                      _ => queue.pause(item.id),
                    },
                  ),
                ),
                TextButton(
                  key: ValueKey('upload-cancel-${item.id}'),
                  onPressed: () async {
                    final confirmed = await confirmLibraryAction(
                      context,
                      title: 'Cancel this sample upload?',
                      message: 'This changes only the demo queue. Your library photo and albums are kept.',
                      confirm: 'Cancel upload',
                      destructive: true,
                    );
                    if (confirmed && context.mounted) {
                      _queueAction(context, () => queue.cancel(item.id));
                    }
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
