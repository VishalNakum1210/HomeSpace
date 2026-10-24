import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_symbols.dart';
import '../design/cartoon_artwork.dart';
import '../design/cartoon_header.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import 'settings_pages.dart';
import 'library_widgets.dart';
import 'trash_page.dart';

String themeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
  ThemeMode.system => 'Follow device',
};

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final repository = HomeScope.of(context);
    final profile = repository.profile;
    final mode = ThemeMode.values.byName(profile.appearance.name);
    final text = Theme.of(context).textTheme;
    final style = SpaceStyle.of(context);
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        key: const PageStorageKey('profile-scroll'),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              spaceBottomPadding(context),
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CartoonHeader(
                    profile: profile,
                    onProfile: () =>
                        openSpacePage<void>(context, const EditProfilePage()),
                  ),
                  Text('Your space', style: text.headlineMedium),
                  const SizedBox(height: 5),
                  Text('Make yourself at home.', style: text.bodyMedium),
                  const SizedBox(height: 18),
                  SpaceCard(
                    color: style.accentSoft,
                    borderColor: style.accent.withValues(alpha: .35),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(width: 60),
                            ProfileAvatar(profile: profile, size: 70),
                            const SizedBox(width: 4),
                            const SizedBox(
                              width: 56,
                              height: 70,
                              child: FittedBox(child: HouseGreeting()),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Hi, ${profile.name}!',
                          textAlign: TextAlign.center,
                          style: text.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your family. Your memories. Your space.',
                          textAlign: TextAlign.center,
                          style: text.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        SpaceButton(
                          key: const ValueKey('edit-profile'),
                          label: 'Edit profile',
                          onPressed: () => openSpacePage<void>(
                            context,
                            const EditProfilePage(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SettingRow(
                    settingKey: const ValueKey('appearance-setting'),
                    icon: Icons.palette_outlined,
                    title: 'Appearance',
                    subtitle: themeLabel(mode),
                    tone: const Color(0xFFFF9600),
                    onTap: () => chooseTheme(context),
                  ),
                  _SettingRow(
                    icon: Icons.accessibility_new_rounded,
                    title: 'Motion & accessibility',
                    subtitle: 'Follows your device preferences',
                    tone: const Color(0xFFA560F5),
                    onTap: () => showMotionInfo(context),
                  ),
                  _SettingRow(
                    settingKey: const ValueKey('trash-setting'),
                    icon: Icons.delete_outline_rounded,
                    title: 'Trash',
                    subtitle: repository.trash.isEmpty
                        ? 'Nothing left behind'
                        : '${repository.trash.length} memories to restore',
                    tone: const Color(0xFFE74742),
                    onTap: () =>
                        openSpacePage<void>(context, const TrashPage()),
                  ),
                  _SettingRow(
                    icon: Icons.home_rounded,
                    title: 'About HomeSpace',
                    subtitle: 'App info and next steps',
                    tone: const Color(0xFF58A800),
                    onTap: () => showAbout(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> chooseTheme(BuildContext context) =>
      openSpacePage<void>(context, const AppearancePage());

  Future<void> showMotionInfo(BuildContext context) => showSpaceSheet<void>(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Comfort comes first',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          MediaQuery.disableAnimationsOf(context)
              ? 'Reduced motion is on. HomeSpace uses immediate state changes instead of moving controls.'
              : 'HomeSpace follows Android’s reduced-motion preference. Turn off system animations to use immediate state changes.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 14),
        Text(
          'Text follows your font-size setting. Every navigation icon has a screen-reader label and a generous touch area.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );

  Future<void> showAbout(BuildContext context) => showSpaceSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SpaceHouse(size: 64),
        const SizedBox(height: 16),
        Text(
          'A home for your memories.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'HomeSpace is a family photo library, designed for the moments you want to keep close.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'Your local profile, theme, favorites, and albums survive an app restart. Connection and upload states are simulations; no files are sent to a server.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 22),
        SpaceButton(
          label: 'Open-source licenses',
          icon: Icons.description_outlined,
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'HomeSpace',
            applicationVersion: '0.4.3',
          ),
        ),
        const SizedBox(height: 10),
      ],
    ),
  );
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Key? settingKey;
  final Color tone;
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.settingKey,
    required this.tone,
  });
  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SpaceCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          key: settingKey,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 5,
          ),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: dark ? .2 : .1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: dark
                  ? Color.lerp(tone, Colors.white, .4)
                  : Color.lerp(tone, Colors.black, .3),
              size: 24,
            ),
          ),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: style.muted),
          onTap: onTap,
        ),
      ),
    );
  }
}
