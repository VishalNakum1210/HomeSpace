import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homespace/application/auto_backup_service.dart';
import 'package:homespace/application/home_scope.dart';
import 'package:homespace/data/local_home_repository.dart';
import 'package:homespace/data/snapshot_store.dart';
import 'package:homespace/pages/backup_settings_page.dart';

void main() {
  test('AutoBackupService defaultFolders contains Camera and WhatsApp', () {
    final folders = AutoBackupService.defaultFolders;
    expect(folders.any((f) => f.id == 'camera'), isTrue);
    expect(folders.any((f) => f.id == 'whatsapp'), isTrue);
    expect(folders.any((f) => f.id == 'screenshots'), isTrue);

    final camera = folders.firstWhere((f) => f.id == 'camera');
    expect(camera.enabled, isTrue);

    final toggled = camera.copyWith(enabled: false);
    expect(toggled.enabled, isFalse);

    final json = toggled.toJson();
    expect(json['id'], 'camera');
    expect(json['enabled'], isFalse);
  });

  testWidgets('BackupSettingsPage renders folder list and Scan button', (tester) async {
    final repository = LocalHomeRepository(
      store: MemorySnapshotStore(),
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      HomeScope(
        repository: repository,
        child: const MaterialApp(
          home: BackupSettingsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Auto-backup folders'), findsOneWidget);
    expect(find.text('Camera (DCIM)'), findsOneWidget);
    expect(find.text('WhatsApp Images'), findsOneWidget);
    expect(find.text('Screenshots'), findsOneWidget);

    // Toggle switch
    final switches = find.byType(Switch);
    expect(switches, findsWidgets);
    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    // Scroll to scan button
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('scan-backup-now')),
      200,
    );
    await tester.pumpAndSettle();

    expect(find.text('Scan & Backup Now'), findsOneWidget);
    expect(find.text('View Upload Queue'), findsOneWidget);

    // Tap Scan button
    await tester.tap(find.byKey(const ValueKey('scan-backup-now')));
    await tester.pumpAndSettle();
  });
}
