import 'package:flutter/material.dart';

import '../application/frontend_session.dart';
import '../application/home_scope.dart';
import '../design/album_widgets.dart';
import '../design/cartoon_artwork.dart';
import '../design/cartoon_header.dart';
import '../design/space_symbols.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import 'backup_settings_page.dart';
import 'connection_page.dart';
import 'library_widgets.dart';
import 'settings_pages.dart';
import 'trash_page.dart';
import 'uploads_page.dart';
import 'admin_users_page.dart';
import 'app_lock_page.dart';
import 'storage_details_page.dart';

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
                    const SizedBox(height: 4),
                    SpaceCard(
                      color: style.accentSoft,
                      borderColor: style.accent.withValues(alpha: .35),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 90,
                            child: Stack(
                              children: [
                                Center(
                                  child: MemberPortrait(
                                    member: FamilyMember(
                                      profile.userId,
                                      profile.name,
                                    ),
                                    size: 82,
                                  ),
                                ),
                                const Positioned(
                                  right: 0,
                                  top: 0,
                                  child: HouseGreeting(profile: true),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                'Hi, ${profile.name}!',
                                textAlign: TextAlign.center,
                                style: text.titleLarge,
                              ),
                              if (profile.isAdmin)
                                ExcludeSemantics(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A73E8).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFF1A73E8),
                                        width: 1,
                                      ),
                                    ),
                                    child: const Text(
                                      'Admin',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1A73E8),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your family. Your memories. Your space.',
                            textAlign: TextAlign.center,
                            style: text.bodyMedium,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: SpaceButton(
                                  key: const ValueKey('edit-profile'),
                                  label: 'Edit profile',
                                  onPressed: () => openSpacePage<void>(
                                    context,
                                    const EditProfilePage(),
                                  ),
                                ),
                              ),
                              if (FrontendSessionScope.maybeOf(context) != null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SpaceButton(
                                    key: const ValueKey('logout'),
                                    label: 'Log out',
                                    icon: Icons.logout_rounded,
                                    backgroundColor: const Color(0xFFFFE7E5),
                                    foregroundColor: const Color(0xFFAD302C),
                                    onPressed: () =>
                                        FrontendSessionScope.maybeOf(context)!.logout(),
                                  ),
                                ),
                              ],
                            ],
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
                      onTap: () =>
                          openSpacePage<void>(context, const AppearancePage()),
                    ),
                    _SettingRow(
                      settingKey: const ValueKey('storage-setting'),
                      icon: Icons.cloud_outlined,
                      title: 'Storage & Space',
                      subtitle: 'Google Photos style meter & cache cleaner',
                      tone: const Color(0xFF1677E8),
                      onTap: () => openSpacePage<void>(
                        context,
                        StorageDetailsPage(repository: repository),
                      ),
                    ),
                    _SettingRow(
                      settingKey: const ValueKey('about-setting'),
                      icon: Icons.home_rounded,
                      title: 'About HomeSpace',
                      subtitle: 'Server, backup, and app info',
                      tone: const Color(0xFF58A800),
                      onTap: () => showAbout(context),
                    ),
                    if (profile.isAdmin)
                      _SettingRow(
                        settingKey: const ValueKey('family-admin-setting'),
                        icon: Icons.group_outlined,
                        title: 'Family members & quotas',
                        subtitle: 'Manage family accounts & storage limits',
                        tone: const Color(0xFF00897B),
                        onTap: () => openSpacePage<void>(
                          context,
                          AdminUsersPage(repository: repository),
                        ),
                      ),
                    _SettingRow(
                      settingKey: const ValueKey('app-lock-setting'),
                      icon: Icons.lock_outline_rounded,
                      title: 'App lock & PIN',
                      subtitle: profile.appLockEnabled
                          ? 'PIN lock active'
                          : 'Off (Touch to set PIN)',
                      tone: const Color(0xFF1E88E5),
                      onTap: () => openSpacePage<void>(
                        context,
                        AppLockPage(repository: repository),
                      ),
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
                  ],
                ),
              ),
            ),
          ],
        ),
    );
  }

  Future<void> _confirmLibraryReset(
    BuildContext context,
    HomeRepository repository,
  ) async {
    final isEmpty = repository.media.isEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isEmpty ? 'Restore Demo Memories?' : 'Clear Demo Memories?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          isEmpty
              ? 'This will restore the bundled demo photos and albums.'
              : 'This will clear all demo photos, albums, and trash so you can test HomeSpace with your real camera roll photos.\n\nYou can add real photos anytime using the + button.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  isEmpty ? const Color(0xFF2E7D32) : const Color(0xFFE74742),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(isEmpty ? 'Restore Demo' : 'Start Fresh (Clear All)'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      if (isEmpty) {
        await repository.resetToDemo();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Demo memories restored.'),
            ),
          );
        }
      } else {
        await repository.clearUserData();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                'Library cleared! Tap + on the Photos tab to add real photos.',
              ),
            ),
          );
        }
      }
    }
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
        const SizedBox(height: 18),
        ListenableBuilder(
          listenable: HomeScope.of(context).connection,
          builder: (context, _) => ListTile(
            key: const ValueKey('server-setting'),
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Home server'),
            subtitle: Text(
              connectionLabel(HomeScope.of(context).connection.status.phase),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(context);
              openSpacePage<void>(context, const ConnectionPage());
            },
          ),
        ),
        ListTile(
          key: const ValueKey('uploads-setting'),
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('Upload queue'),
          subtitle: Text(
            '${HomeScope.of(context).uploads.items.length} sample items',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.pop(context);
            openSpacePage<void>(context, const UploadsPage());
          },
        ),
        ListTile(
          key: const ValueKey('backup-setting'),
          leading: const Icon(Icons.sync_rounded),
          title: const Text('Auto-backup folders'),
          subtitle: const Text('Camera, WhatsApp, Screenshots'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.pop(context);
            openSpacePage<void>(context, const BackupSettingsPage());
          },
        ),
        ListTile(
          key: const ValueKey('library-cleanup-setting'),
          leading: Icon(
            HomeScope.of(context).media.isEmpty
                ? Icons.restart_alt_rounded
                : Icons.cleaning_services_rounded,
            color: const Color(0xFFE65100),
          ),
          title: Text(
            HomeScope.of(context).media.isEmpty
                ? 'Restore Demo Memories'
                : 'Clear Demo Memories',
          ),
          subtitle: Text(
            HomeScope.of(context).media.isEmpty
                ? 'Reload sample photos and albums'
                : 'Start fresh with your real photos',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.pop(context);
            _confirmLibraryReset(context, HomeScope.of(context));
          },
        ),
        const SizedBox(height: 22),
        SpaceButton(
          label: 'Open-source licenses',
          icon: Icons.description_outlined,
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'HomeSpace',
            applicationVersion: '0.8.1',
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
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: dark ? .2 : .1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: dark
                  ? Color.lerp(tone, Colors.white, .4)
                  : Color.lerp(tone, Colors.black, .3),
              size: 21,
            ),
          ),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium!
                .copyWith(fontSize: 16),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(fontSize: 12),
            ),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: style.muted),
          onTap: onTap,
        ),
      ),
    );
  }
}
