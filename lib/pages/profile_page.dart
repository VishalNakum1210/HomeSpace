import 'package:flutter/material.dart';

import '../design/space_symbols.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';

String themeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
  ThemeMode.system => 'Follow device',
};

class ProfilePage extends StatelessWidget {
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onThemeChanged;
  const ProfilePage({
    super.key,
    required this.mode,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
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
                        Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainer,
                            shape: BoxShape.circle,
                            border: Border.all(color: style.accent, width: 3),
                          ),
                          child: Center(
                            child: Text(
                              'M',
                              style: text.headlineLarge!.copyWith(
                                color: style.accentInk,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Hi, Maya!', style: text.headlineMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Your family. Your memories. Your space.',
                          textAlign: TextAlign.center,
                          style: text.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        const SpaceBadge('DEMO PROFILE'),
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
                                'Built around your family',
                                style: text.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'This is the HomeSpace design preview. Your laptop connection and family sharing will arrive in the next stages.',
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
                      'HomeSpace · Design foundation\nAndroid preview 0.1.0',
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

  Future<void> chooseTheme(BuildContext context) => showSpaceSheet<void>(
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
        for (final option in ThemeMode.values)
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
                    ThemeMode.system => Icons.brightness_auto_rounded,
                    ThemeMode.light => Icons.wb_sunny_rounded,
                    ThemeMode.dark => Icons.nightlight_round,
                  }, color: SpaceStyle.of(context).accentInk),
                  title: Text(
                    themeLabel(option),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  trailing: Icon(
                    option == mode
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: SpaceStyle.of(context).accentInk,
                  ),
                  onTap: () {
                    onThemeChanged(option);
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ),
      ],
    ),
  );

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
          'Phase 1 includes the Android design system and three primary page previews. Sample content and appearance changes stay in this session. Server, upload, and sharing services are not connected.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 22),
        SpaceButton(
          label: 'Open-source licenses',
          icon: Icons.description_outlined,
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'HomeSpace',
            applicationVersion: '0.1.0',
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
