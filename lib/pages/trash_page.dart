import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import 'library_widgets.dart';
import 'media_viewer.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});
  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  bool selecting = false;
  final selected = <String>{};
  void clear() => setState(() {
    selecting = false;
    selected.clear();
  });
  void toggle(String id) => setState(() {
    selecting = true;
    selected.contains(id) ? selected.remove(id) : selected.add(id);
  });
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final entries = [...repository.trash]
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    final ids = selected
        .where((id) => entries.any((entry) => entry.mediaId == id))
        .toList();
    final enabled = ids.isNotEmpty && repository.pendingWrites == 0;
    final style = SpaceStyle.of(context);
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) clear();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(selecting ? '${ids.length} selected' : 'Trash'),
          leading: selecting
              ? IconButton(
                  tooltip: 'Cancel selection',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: clear,
                )
              : null,
          actions: [
            if (selecting)
              IconButton(
                tooltip: 'Select all trashed memories',
                icon: const Icon(Icons.select_all_rounded),
                onPressed: () => setState(
                  () => selected.addAll(entries.map((entry) => entry.mediaId)),
                ),
              )
            else if (entries.isNotEmpty) ...[
              IconButton(
                tooltip: 'Select trashed memories',
                icon: const Icon(Icons.checklist_rounded),
                onPressed: () => setState(() => selecting = true),
              ),
              IconButton(
                key: const ValueKey('empty-trash'),
                tooltip: 'Empty Trash',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: repository.pendingWrites > 0
                    ? null
                    : () => deleteTrashedMemories(
                        context,
                        entries.map((entry) => entry.mediaId).toList(),
                      ),
              ),
            ],
          ],
          bottom: !selecting
              ? null
              : SelectionActions(
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('restore-selected'),
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('Restore'),
                      onPressed: !enabled
                          ? null
                          : () async {
                              final saved = await saveLocalChange(
                                context,
                                () => repository.restoreMany(ids),
                              );
                              if (saved && mounted) clear();
                            },
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('delete-selected'),
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Delete forever'),
                      onPressed: !enabled
                          ? null
                          : () async {
                              final saved = await deleteTrashedMemories(
                                context,
                                ids,
                              );
                              if (saved && mounted) clear();
                            },
                    ),
                  ],
                ),
        ),
        body: CustomScrollView(
          key: const ValueKey('trash-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              sliver: SliverToBoxAdapter(
                child: SpaceCard(
                  color: style.accentSoft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.restore_rounded,
                        color: style.accentInk,
                        size: 32,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'A little room to change your mind',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Restore memories to their albums and favorites. This local preview keeps them until you choose Delete forever.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (entries.isEmpty)
              const SliverToBoxAdapter(
                child: SpaceEmpty(
                  icon: Icons.delete_outline_rounded,
                  title: 'Nothing left behind',
                  message: 'Your Trash is empty. Memories you move here will wait for you.',
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: libraryColumns(context),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final photo = repository.mediaById(entry.mediaId)!;
                  final date = entry.deletedAt.toLocal();
                  return MemoryTile(
                    key: ValueKey('trash-${photo.id}'),
                    media: photo,
                    selected: selecting ? selected.contains(photo.id) : null,
                    subtitle: 'Trashed ${date.day}/${date.month}/${date.year}',
                    onLongPress: () => toggle(photo.id),
                    onTap: selecting
                        ? () => toggle(photo.id)
                        : () => openMediaViewer(
                            context,
                            mediaIds: entries
                                .map((item) => item.mediaId)
                                .toList(),
                            initialId: photo.id,
                            inTrash: true,
                          ),
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(
              child: SafeArea(top: false, child: SizedBox(height: 8)),
            ),
          ],
        ),
      ),
    );
  }
}
