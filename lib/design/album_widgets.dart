import 'package:flutter/material.dart';

import 'vector_artwork.dart';

import '../domain/models.dart';
import 'space_theme.dart';

/// Example addresses for the bundled demo members, never used to send invitations.
String? referenceMemberEmail(FamilyMember member) =>
    switch ((member.id, member.name)) {
      ('member-maya', 'Maya') => 'maya@example.com',
      ('member-alex', 'Alex') => 'alex@example.com',
      ('member-sam', 'Sam') => 'sam@example.com',
      _ => null,
    };

class AlbumTheme extends StatelessWidget {
  final Widget child;
  const AlbumTheme({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Theme(
    data: spaceTheme(Theme.of(context).brightness, SpacePage.collections),
    child: child,
  );
}

class MemberPortrait extends StatelessWidget {
  final FamilyMember member;
  final double size;
  const MemberPortrait({super.key, required this.member, this.size = 36});
  @override
  Widget build(BuildContext context) {
    final portrait = switch (member.id) {
      'member-maya' when member.name == 'Maya' => 'maya',
      'member-alex' when member.name == 'Alex' => 'alex',
      'member-sam' when member.name == 'Sam' => 'sam',
      _ => null,
    };
    if (portrait != null) {
      return ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surfaceContainer,
          ),
          child: ClipOval(child: SpaceArtwork(portrait, fit: BoxFit.cover)),
        ),
      );
    }
    final tint = switch (member.id) {
      'member-maya' => const Color(0xFFFFE4B5),
      'member-alex' => const Color(0xFFE9D7FF),
      _ => const Color(0xFFD8EDFF),
    };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tint,
          border: Border.all(
            color: Theme.of(context).colorScheme.surfaceContainer,
            width: 2,
          ),
        ),
        child: Text(
          member.initial,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: size * .38,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF554366),
          ),
        ),
      ),
    );
  }
}

class AlbumPeople extends StatelessWidget {
  final List<FamilyMember> members;
  const AlbumPeople({super.key, required this.members});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    width: members.length.clamp(1, 3) * 26 + 12,
    child: Stack(
      children: [
        for (var index = 0; index < members.length && index < 3; index++)
          Positioned(
            left: index * 26,
            child: MemberPortrait(member: members[index], size: 38),
          ),
      ],
    ),
  );
}

String albumRoleLabel(AlbumRole role) => switch (role) {
  AlbumRole.owner => 'Owner',
  AlbumRole.contributor => 'Contributor',
  AlbumRole.viewer => 'Viewer',
};

String albumMemoryCount(int count) =>
    '$count ${count == 1 ? 'memory' : 'memories'}';
