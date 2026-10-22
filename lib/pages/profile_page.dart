import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_symbols.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import 'local_edit_sheets.dart';

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
                  const SpacePageHeading(
                    SpacePage.profile,
                    subtitle: 'Make yourself at home.',
                  ),
                  SpaceCard(
                    color: style.accentSoft,
                    borderColor: style.accent.withValues(alpha: .35),
                    child: Column(
                      children: [
                        ProfileAvatar(profile: profile, size: 78),
                        const SizedBox(height: 12),
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
                        const SpaceBadge('LOCAL PROFILE'),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          key: const ValueKey('edit-profile'),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit profile'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () => showSpaceSheet<void>(
                            context,
                            const EditProfileSheet(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SpaceSection('A space that feels like you'),
                  SpaceCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _SettingRow(
                          icon: Icons.palette_outlined,
                          title: 'Appearance',
                          subtitle: themeLabel(mode),
                          onTap: () => chooseTheme(context),
                          settingKey: const ValueKey('appearance-setting'),
                        ),
                        Divider(
                          height: 1,
                          indent: 18,
                          endIndent: 18,
                          color: style.border,
                        ),
                        _SettingRow(
                          icon: Icons.accessibility_new_rounded,
                          title: 'Motion & accessibility',
                          subtitle: 'Follows your device preferences',
                          onTap: () => showMotionInfo(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SpaceCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SpaceHouse(size: 45),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'A little space of your own',
                                style: text.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${repository.media.length} memories · ${repository.albums.length} albums\nYour profile, appearance, favorites, and albums are saved on this device.',
                                style: text.bodyMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Sharing and server connections are still demo previews.',
                                style: text.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SpaceButton(
                    label: 'About HomeSpace',
                    icon: Icons.favorite_outline_rounded,
                    onPressed: () => showAbout(context),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Text(
                      'HomeSpace · Local data foundation\nAndroid preview 0.2.0',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium!.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> chooseTheme(BuildContext context) {
    final repository = HomeScope.of(context);
    final mode = repository.profile.appearance;
    return showSpaceSheet<void>(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A little change of scenery',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Choose the look that feels like home.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          for (final option in Appearance.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                selected: option == mode,
                button: true,
                child: Material(
                  color: option == mode
                      ? SpaceStyle.of(context).accentSoft
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: option == mode
                          ? SpaceStyle.of(context).accent
                          : SpaceStyle.of(context).border,
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    key: ValueKey('theme-${option.name}'),
                    minVerticalPadding: 14,
                    leading: Icon(switch (option) {
                      Appearance.system => Icons.brightness_auto_rounded,
                      Appearance.light => Icons.wb_sunny_rounded,
                      Appearance.dark => Icons.nightlight_round,
                    }, color: SpaceStyle.of(context).accentInk),
                    title: Text(
                      themeLabel(ThemeMode.values.byName(option.name)),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    trailing: Icon(
                      option == mode
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: SpaceStyle.of(context).accentInk,
                    ),
                    onTap: () async {
                      final success = await saveLocalChange(
                        context,
                        () => repository.setAppearance(option),
                      );
                      if (success && context.mounted) Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

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
            applicationVersion: '0.2.0',
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
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.settingKey,
  });
  @override
  Widget build(BuildContext context) {
    final style = SpaceStyle.of(context);
    return ListTile(
      key: settingKey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: style.accentSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: style.accentInk, size: 24),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: style.muted),
      onTap: onTap,
    );
  }
}
