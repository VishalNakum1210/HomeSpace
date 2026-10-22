import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_widgets.dart';
import '../design/space_theme.dart';
import '../domain/models.dart';

class AlbumNameSheet extends StatefulWidget {
  final Album? album;
  final List<String> mediaIds;
  const AlbumNameSheet({super.key, this.album, this.mediaIds = const []});
  @override
  State<AlbumNameSheet> createState() => _AlbumNameSheetState();
}

class _AlbumNameSheetState extends State<AlbumNameSheet> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.album?.title ?? '');
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    return Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.album == null
                ? 'A new place for memories'
                : 'Give it a new name',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            'This album is saved locally on your device.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextFormField(
            key: const ValueKey('album-name'),
            controller: name,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Album name',
              hintText: 'Family weekends',
            ),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Give your album a name.'
                : null,
          ),
          const SizedBox(height: 14),
          SpaceButton(
            label: busy
                ? 'Saving…'
                : widget.album == null
                ? 'Create album'
                : 'Save name',
            icon: Icons.photo_album_outlined,
            onPressed: busy
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => busy = true);
                    final success = await saveLocalChange(context, () async {
                      if (widget.album == null) {
                        await repository.createAlbum(
                          name.text,
                          mediaIds: widget.mediaIds,
                        );
                      } else {
                        await repository.renameAlbum(
                          widget.album!.id,
                          name.text,
                        );
                      }
                    });
                    if (!context.mounted) return;
                    setState(() => busy = false);
                    if (success) Navigator.pop(context);
                  },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({super.key});
  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  final form = GlobalKey<FormState>();
  TextEditingController? _name;
  AvatarTone? _tone;
  bool busy = false;
  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final profile = repository.profile;
    _name ??= TextEditingController(text: profile.name);
    _tone ??= profile.avatarTone;
    return Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Make it yours', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'A name and a little color for your local profile.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextFormField(
            key: const ValueKey('profile-name'),
            controller: _name,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Your name'),
            textCapitalization: TextCapitalization.words,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter your name.'
                : null,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final tone in AvatarTone.values)
                Semantics(
                  button: true,
                  selected: tone == _tone,
                  label: '${tone.name} avatar',
                  child: InkWell(
                    key: ValueKey('avatar-${tone.name}'),
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _tone = tone),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tone == _tone
                              ? SpaceStyle.of(context).accentInk
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ProfileAvatar(
                        profile: profile.copyWith(avatarTone: tone),
                        size: 46,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SpaceButton(
            label: busy ? 'Saving…' : 'Save profile',
            icon: Icons.check_rounded,
            onPressed: busy
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => busy = true);
                    final success = await saveLocalChange(
                      context,
                      () => repository.updateProfile(_name!.text, _tone!),
                    );
                    if (!context.mounted) return;
                    setState(() => busy = false);
                    if (success) Navigator.pop(context);
                  },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class AlbumPickerSheet extends StatelessWidget {
  final String mediaId;
  const AlbumPickerSheet({super.key, required this.mediaId});
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
          'One memory can belong to more than one album.',
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
              album.mediaIds.contains(mediaId)
                  ? 'Already in this album'
                  : '${repository.photosFor(album).length} photos',
            ),
            trailing: album.mediaIds.contains(mediaId)
                ? const Icon(Icons.check_rounded)
                : const Icon(Icons.add_rounded),
            onTap:
                album.mediaIds.contains(mediaId) || repository.pendingWrites > 0
                ? null
                : () async {
                    final success = await saveLocalChange(
                      context,
                      () => repository.addToAlbum(album.id, mediaId),
                    );
                    if (success && context.mounted) Navigator.pop(context);
                  },
          ),
        const SizedBox(height: 16),
        SpaceButton(
          label: 'Create a new album',
          icon: Icons.add_rounded,
          onPressed: () => showSpaceSheet<void>(
            context,
            AlbumNameSheet(mediaIds: [mediaId]),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
