import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_widgets.dart';
import '../design/space_theme.dart';
import '../domain/models.dart';
import 'album_editor_page.dart';

class AlbumPickerSheet extends StatelessWidget {
  final List<String> mediaIds;
  const AlbumPickerSheet({super.key, required this.mediaIds});
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final albums = repository.albums
        .where(
          (album) => [
            AlbumRole.owner,
            AlbumRole.contributor,
          ].contains(album.roleFor(repository.profile.userId)),
        )
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A place in your story',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          '${mediaIds.length == 1 ? 'One memory' : '${mediaIds.length} memories'} can belong to more than one album.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final album in albums)
          ListTile(
            key: ValueKey('add-to-${album.id}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(
              Icons.photo_album_outlined,
              color: SpaceStyle.of(context).accentInk,
            ),
            title: Text(album.title),
            subtitle: Text(
              album.mediaIds.toSet().containsAll(mediaIds)
                  ? 'Already in this album'
                  : '${repository.photosFor(album).length} photos',
            ),
            trailing: album.mediaIds.toSet().containsAll(mediaIds)
                ? const Icon(Icons.check_rounded)
                : const Icon(Icons.add_rounded),
            onTap:
                album.mediaIds.toSet().containsAll(mediaIds) ||
                    repository.pendingWrites > 0
                ? null
                : () async {
                    final success = await saveLocalChange(
                      context,
                      () => repository.addManyToAlbum(album.id, mediaIds),
                    );
                    if (success && context.mounted) {
                      popSpaceRouteIfCurrent(context, true);
                    }
                  },
          ),
        const SizedBox(height: 16),
        SpaceButton(
          label: 'Create a new album',
          icon: Icons.add_rounded,
          onPressed: repository.pendingWrites > 0
              ? null
              : () async {
                  final created = await openAlbumEditor(
                    context,
                    mediaIds: mediaIds,
                  );
                  if (created != null && context.mounted) {
                    popSpaceRouteIfCurrent(context, true);
                  }
                },
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
