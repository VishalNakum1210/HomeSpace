import 'package:flutter/material.dart';

import '../application/auto_backup_service.dart';
import '../application/device_media_service.dart';
import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import 'library_widgets.dart';
import 'uploads_page.dart';

class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  List<BackupFolderConfig> folders = List.of(AutoBackupService.defaultFolders);
  bool loading = false;
  bool scanning = false;
  String? statusMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await AutoBackupService.loadFolders();
    if (!mounted) return;
    setState(() {
      folders = List.of(loaded);
      loading = false;
    });
  }

  Future<void> _toggleFolder(int index, bool enabled) async {
    final next = [...folders];
    next[index] = next[index].copyWith(enabled: enabled);
    setState(() {
      folders = next;
    });
    await AutoBackupService.saveFolders(folders);
  }

  Future<void> _runBackupNow() async {
    setState(() {
      scanning = true;
      statusMessage = null;
    });

    final hasPerm = await DeviceMediaService.checkStoragePermission();
    if (!hasPerm) {
      final granted = await DeviceMediaService.requestStoragePermission();
      if (!granted) {
        if (!mounted) return;
        setState(() {
          scanning = false;
          statusMessage = 'Storage permission was not granted. Please enable photo/video permissions in Settings.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Storage permission required to backup photos and videos.'),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    final repository = HomeScope.of(context);
    final count = await AutoBackupService.scanAndQueueBackup(
      folders: folders,
      repository: repository,
    );

    if (!mounted) return;
    setState(() {
      scanning = false;
      statusMessage = count > 0
          ? 'Successfully queued $count new photos for backup!'
          : 'All photos from selected folders are already backed up or queued.';
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Text(statusMessage!),
        action: count > 0
            ? SnackBarAction(
                label: 'View Queue',
                onPressed: () {
                  messenger.clearSnackBars();
                  openSpacePage<void>(context, const UploadsPage());
                },
              )
            : null,
      ),
    );
  }

  IconData _iconForFolder(String id) {
    switch (id) {
      case 'camera':
        return Icons.camera_alt_rounded;
      case 'whatsapp':
        return Icons.chat_rounded;
      case 'screenshots':
        return Icons.screenshot_rounded;
      case 'downloads':
        return Icons.download_rounded;
      case 'pictures':
        return Icons.photo_library_rounded;
      default:
        return Icons.folder_rounded;
    }
  }

  Color _colorForFolder(String id) {
    switch (id) {
      case 'camera':
        return const Color(0xFF1677E8);
      case 'whatsapp':
        return const Color(0xFF25D366);
      case 'screenshots':
        return const Color(0xFF8E24AA);
      case 'downloads':
        return const Color(0xFFFF9800);
      case 'pictures':
        return const Color(0xFF009688);
      default:
        return const Color(0xFF607D8B);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: spaceTheme(Theme.of(context).brightness, SpacePage.profile),
        child: Builder(
          builder: (context) {
            final text = Theme.of(context).textTheme;
            final style = SpaceStyle.of(context);

            return Scaffold(
              appBar: AppBar(
                title: const Text('Auto-backup folders'),
                centerTitle: true,
              ),
              body: SafeArea(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        children: [
                          SpaceCard(
                            color: style.accentSoft,
                            borderColor: style.accent.withValues(alpha: .35),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: style.accent.withValues(alpha: .15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.sync_rounded,
                                    size: 28,
                                    color: style.accent,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Continuous Protection',
                                        style: text.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Select phone folders to automatically preserve memories on your HomeSpace server.',
                                        style: text.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'DEVICE FOLDERS',
                            style: text.labelSmall?.copyWith(
                              letterSpacing: 1.2,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (var i = 0; i < folders.length; i++) ...[
                            () {
                              final config = folders[i];
                              final count = AutoBackupService.countPhotosInFolder(config);
                              final activeDir = AutoBackupService.findActiveFolder(config);
                              final detected = activeDir != null;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Material(
                                  color: Theme.of(context).cardColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: Colors.black.withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: SwitchListTile.adaptive(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    secondary: CircleAvatar(
                                      backgroundColor: _colorForFolder(config.id).withValues(alpha: .15),
                                      foregroundColor: _colorForFolder(config.id),
                                      child: Icon(_iconForFolder(config.id), size: 22),
                                    ),
                                    title: Text(
                                      config.name,
                                      style: text.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          config.description,
                                          style: text.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              detected
                                                  ? Icons.check_circle_rounded
                                                  : Icons.info_outline_rounded,
                                              size: 13,
                                              color: detected ? Colors.green : Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              detected
                                                  ? '$count items found on device'
                                                  : 'Folder not found',
                                              style: text.labelSmall?.copyWith(
                                                color: detected ? Colors.green.shade700 : Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    value: config.enabled,
                                    onChanged: (val) => _toggleFolder(i, val),
                                  ),
                                ),
                              );
                            }(),
                          ],
                          const SizedBox(height: 20),
                          if (statusMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFA5D6A7)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: Color(0xFF2E7D32),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      statusMessage!,
                                      style: text.bodySmall?.copyWith(
                                        color: const Color(0xFF1B5E20),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          SpaceButton(
                            key: const ValueKey('scan-backup-now'),
                            label: scanning ? 'Scanning folders…' : 'Scan & Backup Now',
                            icon: scanning ? Icons.hourglass_top_rounded : Icons.cloud_upload_rounded,
                            backgroundColor: const Color(0xFF1677E8),
                            foregroundColor: Colors.white,
                            onPressed: scanning ? null : _runBackupNow,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.list_alt_rounded),
                            label: const Text('View Upload Queue'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () =>
                                openSpacePage<void>(context, const UploadsPage()),
                          ),
                        ],
                      ),
              ),
            );
          },
        ),
      );
}
