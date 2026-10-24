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
  Widget build(BuildContext context) => Theme(
    data: spaceTheme(Theme.of(context).brightness, SpacePage.profile),
    child: Builder(builder: _page),
  );

  Widget _page(BuildContext context) {
    final repository = HomeScope.of(context);
    final entries = [...repository.trash]
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    final ids = selected
        .where((id) => entries.any((entry) => entry.mediaId == id))
        .toList();
    final enabled = ids.isNotEmpty && repository.pendingWrites == 0;
    final text = Theme.of(context).textTheme;
    final purple = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFDBC4FF)
        : const Color(0xFF7035B4);
    final restore = OutlinedButton.icon(
      key: const ValueKey('restore-selected'),
      icon: const Icon(Icons.restore_rounded),
      label: Text('Restore (${ids.length})'),
      style: OutlinedButton.styleFrom(
        foregroundColor: purple,
        minimumSize: const Size(48, 54),
        side: BorderSide(color: purple),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: !enabled
          ? null
          : () async {
              final saved = await saveLocalChange(
                context,
                () => repository.restoreMany(ids),
              );
              if (saved && mounted) clear();
            },
    );
    final delete = SpaceButton(
      key: const ValueKey('delete-selected'),
      label: 'Delete (${ids.length})',
      icon: Icons.delete_outline_rounded,
      backgroundColor: const Color(0xFFB42318),
      foregroundColor: Colors.white,
      onPressed: !enabled
          ? null
          : () async {
              final saved = await deleteTrashedMemories(context, ids);
              if (saved && mounted) clear();
            },
    );
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) clear();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(selecting ? '${ids.length} selected' : 'Trash'),
          centerTitle: true,
          leading: selecting
              ? IconButton(
                  tooltip: 'Cancel selection',
                  onPressed: clear,
                  icon: const Icon(Icons.close_rounded),
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
            else if (entries.isNotEmpty)
              IconButton(
                tooltip: 'Select trashed memories',
                icon: const Icon(Icons.checklist_rounded),
                onPressed: () => setState(() => selecting = true),
              ),
          ],
        ),
        body: CustomScrollView(
          key: const ValueKey('trash-scroll'),
          slivers: [
            if (entries.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Text(
                        '${entries.length} ${entries.length == 1 ? 'memory' : 'memories'}',
                        style: text.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Stored until you delete them.',
                        style: text.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
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
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
                    showSubtitle: false,
                    onLongPress: () => toggle(photo.id),
                    onTap: selecting
                        ? () => toggle(photo.id)
                        : () => openMediaViewer(
                            context,
                            mediaIds: entries
                                .map((entry) => entry.mediaId)
                                .toList(),
                            initialId: photo.id,
                            inTrash: true,
                          ),
                  );
                },
              ),
            ),
            if (entries.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      if (selecting) ...[
                        if (MediaQuery.textScalerOf(context).scale(14) > 20)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              restore,
                              const SizedBox(height: 12),
                              delete,
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(child: restore),
                              const SizedBox(width: 12),
                              Expanded(child: delete),
                            ],
                          ),
                        const SizedBox(height: 18),
                        const Divider(),
                      ],
                      TextButton(
                        key: const ValueKey('empty-trash'),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: repository.pendingWrites > 0
                            ? null
                            : () async {
                                final saved = await deleteTrashedMemories(
                                  context,
                                  entries
                                      .map((entry) => entry.mediaId)
                                      .toList(),
                                );
                                if (saved && mounted) clear();
                              },
                        child: const Text('Empty Trash'),
                      ),
                    ],
                  ),
                ),
              ),
            const SliverToBoxAdapter(
              child: SafeArea(top: false, child: SizedBox(height: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
