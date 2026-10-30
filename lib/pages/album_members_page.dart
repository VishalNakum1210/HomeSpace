import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/album_widgets.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import 'library_widgets.dart';

class AlbumMembersPage extends StatelessWidget {
  final String albumId;
  const AlbumMembersPage({super.key, required this.albumId});
  @override
  Widget build(BuildContext context) => AlbumTheme(
    child: Builder(
      builder: (context) {
        final repository = HomeScope.of(context);
        final album = repository.albums
            .where((album) => album.id == albumId)
            .firstOrNull;
        if (album == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Members')),
            body: const SpaceEmpty(
              icon: Icons.people_outline_rounded,
              title: 'This album is unavailable',
              message: 'Return to Collections and try again.',
            ),
          );
        }
        final owner =
            album.roleFor(repository.profile.userId) == AlbumRole.owner;
        final cover = repository.coverFor(album);
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: Text(album.title), centerTitle: true),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: cover == null
                          ? ColoredBox(
                              color: SpaceStyle.of(context).accentSoft,
                              child: const Icon(Icons.photo_album_outlined),
                            )
                          : MediaThumbnail(media: cover),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(album.title, style: text.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          '${albumMemoryCount(repository.photosFor(album).length)} · ${album.shared ? 'Shared album' : 'Personal album'}',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Text('Members', style: text.titleLarge),
              const SizedBox(height: 5),
              Text('Sharing applies to this album.', style: text.bodyMedium),
              const SizedBox(height: 16),
              for (final membership in album.memberships)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SpaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final person = repository.memberById(membership.userId);
                        final editable =
                            owner && membership.role != AlbumRole.owner;
                        final large =
                            MediaQuery.textScalerOf(context).scale(14) > 19 ||
                            constraints.maxWidth < 290;
                        final control = !editable
                            ? Text(
                                albumRoleLabel(membership.role),
                                style: text.bodyMedium,
                              )
                            : OutlinedButton.icon(
                                key: ValueKey(
                                  'member-options-${membership.userId}',
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  side: BorderSide(
                                    color: SpaceStyle.of(context).border,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                label: Text(albumRoleLabel(membership.role)),
                                icon: const Icon(
                                  Icons.expand_more_rounded,
                                  size: 18,
                                ),
                                onPressed: repository.pendingWrites > 0
                                    ? null
                                    : () => showSpaceSheet<void>(
                                        context,
                                        MemberPermissionsSheet(
                                          albumId: album.id,
                                          userId: membership.userId,
                                        ),
                                      ),
                              );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                MemberPortrait(member: person, size: 40),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${person.name}${person.id == repository.profile.userId ? ' (you)' : ''}',
                                    style: text.titleMedium,
                                  ),
                                ),
                                if (!large) ...[
                                  const SizedBox(width: 8),
                                  control,
                                ],
                              ],
                            ),
                            if (large)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: control,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              if (owner) ...[
                const SizedBox(height: 14),
                SpaceButton(
                  key: const ValueKey('add-family-member'),
                  label: 'Add member',
                  icon: Icons.person_add_alt_rounded,
                  onPressed: repository.pendingWrites > 0
                      ? null
                      : () => showSpaceSheet<void>(
                          context,
                          AddFamilyMemberSheet(albumId: albumId),
                        ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class MemberPermissionsSheet extends StatefulWidget {
  final String albumId;
  final String userId;
  const MemberPermissionsSheet({
    super.key,
    required this.albumId,
    required this.userId,
  });
  @override
  State<MemberPermissionsSheet> createState() => _MemberPermissionsSheetState();
}

class _MemberPermissionsSheetState extends State<MemberPermissionsSheet> {
  AlbumRole? selected;
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final album = repository.albums
        .where((album) => album.id == widget.albumId)
        .firstOrNull;
    final current = album?.roleFor(widget.userId);
    if (album == null || current == null) {
      return const Text('This member is no longer in the album.');
    }
    selected ??= current;
    final allowed =
        album.roleFor(repository.profile.userId) == AlbumRole.owner &&
        current != AlbumRole.owner;
    final busy = repository.pendingWrites > 0;
    final person = repository.memberById(widget.userId);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text('Set permissions', style: text.titleLarge)),
            IconButton(
              tooltip: 'Close permissions',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            MemberPortrait(member: person, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.name, style: text.titleMedium),
                  Text(
                    referenceMemberEmail(person) ?? 'Email not provided',
                    style: text.bodyMedium,
                  ),
                ],
              ),
            ),
            if (allowed)
              PopupMenuButton<String>(
                tooltip: 'Member options',
                enabled: !busy,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'remove',
                    key: ValueKey('remove-album-member'),
                    child: Text('Remove member'),
                  ),
                ],
                onSelected: (_) async {
                  final confirmed = await confirmLibraryAction(
                    context,
                    title: 'Remove this member?',
                    message: 'Their memories stay in the album. You can add this family member again later.',
                    confirm: 'Remove member',
                  );
                  if (!confirmed || !context.mounted) return;
                  final saved = await saveLocalChange(
                    context,
                    () =>
                        repository.removeMember(widget.albumId, widget.userId),
                  );
                  if (saved && context.mounted) popSpaceRouteIfCurrent(context);
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        for (final role in [AlbumRole.viewer, AlbumRole.contributor])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              checked: selected == role,
              inMutuallyExclusiveGroup: true,
              button: true,
              child: Material(
                color: selected == role
                    ? const Color(0xFF1677E8).withValues(alpha: .08)
                    : Theme.of(context).colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: selected == role
                        ? const Color(0xFF1677E8)
                        : SpaceStyle.of(context).border,
                    width: selected == role ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('permission-${role.name}'),
                  onTap: !allowed || busy
                      ? null
                      : () => setState(() => selected = role),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          selected == role
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: selected == role
                              ? const Color(0xFF1677E8)
                              : SpaceStyle.of(context).muted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                albumRoleLabel(role),
                                style: text.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                role == AlbumRole.viewer
                                    ? 'Can view memories in this album.'
                                    : 'Can add memories and remove their own additions.',
                                style: text.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        SpaceButton(
          key: const ValueKey('save-member-permissions'),
          label: 'Save permissions',
          onPressed: !allowed || busy || selected == current
              ? null
              : () async {
                  final saved = await saveLocalChange(
                    context,
                    () => repository.setMemberRole(
                      widget.albumId,
                      widget.userId,
                      selected!,
                    ),
                  );
                  if (saved && context.mounted) popSpaceRouteIfCurrent(context);
                },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class AddFamilyMemberSheet extends StatefulWidget {
  final String albumId;
  const AddFamilyMemberSheet({super.key, required this.albumId});
  @override
  State<AddFamilyMemberSheet> createState() => _AddFamilyMemberSheetState();
}

class _AddFamilyMemberSheetState extends State<AddFamilyMemberSheet> {
  String? memberId;
  AlbumRole role = AlbumRole.viewer;
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final album = repository.albums
        .where((item) => item.id == widget.albumId)
        .firstOrNull;
    final people = repository.snapshot.family
        .where((person) => album?.roleFor(person.id) == null)
        .toList();
    if (people.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add member', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          const Text('Everyone in your family is already here.'),
          const SizedBox(height: 18),
          SpaceButton(label: 'Done', onPressed: () => Navigator.pop(context)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Add family member',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          'Choose a sample family member and their role. No invitations are sent.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        for (final person in people)
          ListTile(
            key: ValueKey('choose-member-${person.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(person.name),
            trailing: Icon(
              memberId == person.id
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
            ),
            onTap: () => setState(() => memberId = person.id),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<AlbumRole>(
          key: const ValueKey('new-member-role'),
          initialValue: role,
          decoration: const InputDecoration(labelText: 'Album role'),
          items: const [
            DropdownMenuItem(value: AlbumRole.viewer, child: Text('Viewer')),
            DropdownMenuItem(
              value: AlbumRole.contributor,
              child: Text('Contributor'),
            ),
          ],
          onChanged: (value) =>
              setState(() => role = value ?? AlbumRole.viewer),
        ),
        const SizedBox(height: 20),
        SpaceButton(
          label: 'Add to this album',
          icon: Icons.person_add_alt_rounded,
          onPressed: memberId == null || repository.pendingWrites > 0
              ? null
              : () async {
                  final saved = await saveLocalChange(
                    context,
                    () => repository.setMemberRole(
                      widget.albumId,
                      memberId!,
                      role,
                    ),
                  );
                  if (saved && context.mounted) popSpaceRouteIfCurrent(context);
                },
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
