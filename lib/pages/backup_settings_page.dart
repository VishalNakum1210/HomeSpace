import 'package:flutter/material.dart';

import '../application/auto_backup_service.dart';
import '../application/device_media_service.dart';
import '../application/home_scope.dart';
import '../data/demo_remote_repositories.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/repositories.dart';
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
  bool wifiOnly = false;
  bool requireCharging = false;
  bool hasInitialChoice = true;
  FreeUpSpaceResult? freeUpResult;
  bool calculatingFreeUp = false;
  bool freeingUp = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await AutoBackupService.loadFolders();
    final wifi = await AutoBackupService.isWifiOnly();
    final charging = await AutoBackupService.isRequireCharging();
    final initialChoice = await AutoBackupService.hasInitialChoiceMade();
    if (!mounted) return;
    setState(() {
      folders = List.of(loaded);
      wifiOnly = wifi;
      requireCharging = charging;
      hasInitialChoice = initialChoice;
      loading = false;
    });
    _recalculateFreeUpSpace();
  }

  Future<void> _recalculateFreeUpSpace() async {
    if (!mounted) return;
    setState(() => calculatingFreeUp = true);
    final repo = HomeScope.of(context);
    final result = await AutoBackupService.calculateFreeUpSpace(
      folders: folders,
      repository: repo,
    );
    if (!mounted) return;
    setState(() {
      freeUpResult = result;
      calculatingFreeUp = false;
    });
  }

  Future<void> _toggleWifiOnly(bool val) async {
    setState(() => wifiOnly = val);
    await AutoBackupService.setWifiOnly(val);
  }

  Future<void> _toggleRequireCharging(bool val) async {
    setState(() => requireCharging = val);
    await AutoBackupService.setRequireCharging(val);
  }

  Future<void> _setInitialBackupChoice(bool allHistory) async {
    await AutoBackupService.setInitialChoiceMade(true);
    if (!mounted) return;
    setState(() => hasInitialChoice = true);
    await _runBackupNow(onlyNewPhotos: !allHistory);
  }

  Future<void> _runFreeUpSpace() async {
    final result = freeUpResult;
    if (result == null || result.totalCount == 0) return;

    final confirmed = await confirmLibraryAction(
      context,
      title: 'Free up device space?',
      message:
          'Remove ${result.totalCount} item${result.totalCount == 1 ? "" : "s"} (${result.formattedSize}) that are backed up safely to your HomeSpace server? You can still view or download them anytime.',
      confirm: 'Free up ${result.formattedSize}',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => freeingUp = true);
    final count = await AutoBackupService.freeUpSpace(
      files: result.candidateFiles,
    );
    if (!mounted) return;
    setState(() => freeingUp = false);

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Freed up space! Removed $count local file${count == 1 ? "" : "s"}.'),
      ),
    );
    _recalculateFreeUpSpace();
  }

  Future<void> _toggleFolder(int index, bool enabled) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = [...folders];
    final prev = next[index];
    next[index] = prev.copyWith(
      enabled: enabled,
      enabledAt: enabled ? now : null,
      clearEnabledAt: !enabled,
    );
    setState(() {
      folders = next;
    });
    await AutoBackupService.saveFolders(folders);
  }

  Future<void> _runBackupNow({bool onlyNewPhotos = true}) async {
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
      onlyNewPhotos: onlyNewPhotos,
    );

    if (!mounted) return;
    setState(() {
      scanning = false;
      statusMessage = count > 0
          ? 'Successfully queued $count ${onlyNewPhotos ? "new " : ""}photos for backup!'
          : 'All selected photos are already backed up or queued.';
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
    _recalculateFreeUpSpace();
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
                          if (!hasInitialChoice) ...[
                            SpaceCard(
                              color: const Color(0xFFF3E5F5),
                              borderColor: const Color(0xFFCE93D8),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.stars_rounded, color: Color(0xFF8E24AA), size: 24),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'First-Time Backup Setup',
                                          style: text.titleSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF4A148C),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Choose how you would like to protect your photos and videos:',
                                    style: text.bodySmall?.copyWith(color: const Color(0xFF4A148C)),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          key: const ValueKey('initial-backup-all-btn'),
                                          icon: const Icon(Icons.all_inclusive_rounded, size: 16),
                                          label: const Text('All past photos', style: TextStyle(fontSize: 12)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF8E24AA),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: scanning ? null : () => _setInitialBackupChoice(true),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          key: const ValueKey('initial-backup-new-btn'),
                                          icon: const Icon(Icons.today_rounded, size: 16),
                                          label: const Text('Only new photos', style: TextStyle(fontSize: 12)),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: scanning ? null : () => _setInitialBackupChoice(false),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
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
                                        'New photos and videos captured after enabling will be automatically preserved on your HomeSpace server.',
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
                          Text(
                            'SAFEGUARDS & CONDITIONS',
                            style: text.labelSmall?.copyWith(
                              letterSpacing: 1.2,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: Theme.of(context).cardColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Column(
                                children: [
                                  SwitchListTile.adaptive(
                                    key: const ValueKey('backup-wifi-only-switch'),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    secondary: CircleAvatar(
                                      backgroundColor: const Color(0xFF1677E8).withValues(alpha: .15),
                                      foregroundColor: const Color(0xFF1677E8),
                                      child: const Icon(Icons.wifi_rounded, size: 22),
                                    ),
                                    title: Text(
                                      'Back up over Wi-Fi only',
                                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      'Avoid cellular data usage and extra carrier fees',
                                      style: text.bodySmall,
                                    ),
                                    value: wifiOnly,
                                    onChanged: _toggleWifiOnly,
                                  ),
                                  Divider(height: 1, indent: 64, endIndent: 16, color: Colors.grey.withValues(alpha: 0.15)),
                                  SwitchListTile.adaptive(
                                    key: const ValueKey('backup-require-charging-switch'),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    secondary: CircleAvatar(
                                      backgroundColor: const Color(0xFFFF9800).withValues(alpha: .15),
                                      foregroundColor: const Color(0xFFFF9800),
                                      child: const Icon(Icons.battery_charging_full_rounded, size: 22),
                                    ),
                                    title: Text(
                                      'Back up only while charging',
                                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      'Conserve battery power on the move',
                                      style: text.bodySmall,
                                    ),
                                    value: requireCharging,
                                    onChanged: _toggleRequireCharging,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'FREE UP DEVICE SPACE',
                            style: text.labelSmall?.copyWith(
                              letterSpacing: 1.2,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SpaceCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4CAF50).withValues(alpha: .15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.cleaning_services_rounded,
                                        size: 24,
                                        color: Color(0xFF2E7D32),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Free up device space',
                                            style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            calculatingFreeUp
                                                ? 'Calculating backed-up items…'
                                                : (freeUpResult != null && freeUpResult!.totalCount > 0)
                                                    ? '${freeUpResult!.totalCount} item${freeUpResult!.totalCount == 1 ? "" : "s"} (${freeUpResult!.formattedSize}) backed up safely'
                                                    : 'No backed-up items to remove right now',
                                            style: text.bodySmall?.copyWith(color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Items backed up to your HomeSpace server can be safely deleted from this device. They will stay in your library and stream seamlessly whenever viewed.',
                                  style: text.bodySmall?.copyWith(color: Colors.grey.shade700),
                                ),
                                const SizedBox(height: 14),
                                SpaceButton(
                                  key: const ValueKey('free-up-space-btn'),
                                  label: freeingUp
                                      ? 'Freeing up…'
                                      : (freeUpResult != null && freeUpResult!.totalCount > 0)
                                          ? 'Free up ${freeUpResult!.formattedSize}'
                                          : 'Device storage is optimized',
                                  icon: Icons.delete_sweep_rounded,
                                  backgroundColor: (freeUpResult != null && freeUpResult!.totalCount > 0)
                                      ? const Color(0xFF2E7D32)
                                      : Colors.grey.shade300,
                                  foregroundColor: (freeUpResult != null && freeUpResult!.totalCount > 0)
                                      ? Colors.white
                                      : Colors.grey.shade700,
                                  onPressed: (freeingUp || calculatingFreeUp || freeUpResult == null || freeUpResult!.totalCount == 0)
                                      ? null
                                      : _runFreeUpSpace,
                                ),
                              ],
                            ),
                          ),
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
                            onPressed: scanning ? null : () => _runBackupNow(onlyNewPhotos: true),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            key: const ValueKey('backup-all-history'),
                            icon: const Icon(Icons.history_rounded),
                            label: const Text('Backup All Past Photos'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: scanning ? null : () => _runBackupNow(onlyNewPhotos: false),
                          ),
                          const SizedBox(height: 12),
                          ListenableBuilder(
                            listenable: HomeScope.of(context).uploads,
                            builder: (context, _) {
                              final queue = HomeScope.of(context).uploads;
                              final remaining = queue is! DemoUploadRepository
                                  ? queue.remainingCount
                                  : 0;
                              return OutlinedButton.icon(
                                key: const ValueKey('view-upload-queue-btn'),
                                icon: const Icon(Icons.list_alt_rounded),
                                label: Text(
                                  remaining > 0
                                      ? 'View Upload Queue ($remaining remaining)'
                                      : 'View Upload Queue',
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: () =>
                                    openSpacePage<void>(context, const UploadsPage()),
                              );
                            },
                          ),
                        ],
                      ),
              ),
            );
          },
        ),
      );
}
