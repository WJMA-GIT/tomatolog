import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomatolog/services/sync_backup_models.dart';
import 'package:tomatolog/widgets/webdav_settings_section.dart';

void main() {
  testWidgets('shows sync and backup as separate settings', (tester) async {
    Future<void> nothing() async {}

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebDavSettingsSection(
              serverUrl: 'https://example.com/dav/',
              username: 'tomato',
              hasSavedPassword: true,
              autoSyncEnabled: true,
              remoteDataUpdatedAt: DateTime(2026, 8, 1, 20),
              autoBackupEnabled: true,
              backupFrequency: BackupFrequency.daily,
              archives: [
                BackupEntry(
                  fileName: 'backup-1.json',
                  createdAt: DateTime(2026, 8, 2, 9, 30),
                  sizeBytes: 1024,
                ),
              ],
              onSaveConnection: (_) async {},
              onTestConnection: (_) async {},
              onSyncNow: () async => true,
              onAutoSyncChanged: (_) async {},
              onBackupNow: nothing,
              onExportLocalBackup: () async => true,
              onAutoBackupChanged: (_) async {},
              onBackupFrequencyChanged: (_) async {},
              onRestoreArchive: (_) async {},
              onDeleteArchive: (_) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('自动同步'), findsOneWidget);
    expect(find.text('自动备份'), findsOneWidget);
    expect(find.text('导出本地备份'), findsOneWidget);
    expect(find.text('2026-08-02 09:30'), findsOneWidget);

    final autoBackupY = tester.getTopLeft(find.text('自动备份')).dy;
    final frequencyY = tester.getTopLeft(find.text('备份频率')).dy;
    final localExportY = tester.getTopLeft(find.text('导出本地备份')).dy;
    expect(autoBackupY, lessThan(frequencyY));
    expect(frequencyY, lessThan(localExportY));
  });

  testWidgets('shows toast feedback when sync is cancelled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebDavSettingsSection(
              serverUrl: 'https://example.com/dav/',
              username: 'tomato',
              hasSavedPassword: true,
              autoSyncEnabled: false,
              remoteDataUpdatedAt: null,
              autoBackupEnabled: false,
              backupFrequency: BackupFrequency.daily,
              archives: const [],
              onSaveConnection: (_) async {},
              onTestConnection: (_) async {},
              onSyncNow: () async => false,
              onAutoSyncChanged: (_) async {},
              onBackupNow: () async {},
              onExportLocalBackup: () async => true,
              onAutoBackupChanged: (_) async {},
              onBackupFrequencyChanged: (_) async {},
              onRestoreArchive: (_) async {},
              onDeleteArchive: (_) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('立即同步'));
    await tester.pump();

    expect(find.text('同步已取消'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final toastRect = tester.getRect(find.text('同步已取消'));
    expect(toastRect.center.dy, greaterThan(screenHeight / 2));
    expect(toastRect.bottom, lessThanOrEqualTo(screenHeight - 100));
  });
}
