import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../services/webdav_sync_manager.dart';
import '../widgets/webdav_settings_section.dart';

const _accentOptions = [
  (label: '珊瑚红', color: Color(0xFFE05446)),
  (label: '海湾蓝', color: Color(0xFF4169C1)),
  (label: '松石绿', color: Color(0xFF27816D)),
  (label: '鸢尾紫', color: Color(0xFF7255B5)),
  (label: '莓果粉', color: Color(0xFFB94F70)),
  (label: '琥珀橙', color: Color(0xFFB86828)),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  Map<String, bool> _notificationStatus = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshNotificationStatus();
    final webDav = widget.controller.webDav;
    if (webDav?.configured == true) {
      unawaited(webDav!.refreshRemoteState().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshNotificationStatus();
  }

  Future<void> _refreshNotificationStatus() async {
    final status = await widget.controller.notificationStatus();
    if (mounted) setState(() => _notificationStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundPath = widget.controller.backgroundImagePath;
    final batteryUnrestricted =
        _notificationStatus['batteryUnrestricted'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text('主题', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          SegmentedButton<AppThemePreference>(
            segments: const [
              ButtonSegment(
                value: AppThemePreference.system,
                icon: Icon(Icons.settings_suggest_outlined),
                label: Text('跟随系统'),
              ),
              ButtonSegment(
                value: AppThemePreference.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('浅色'),
              ),
              ButtonSegment(
                value: AppThemePreference.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('纯黑'),
              ),
            ],
            selected: {widget.controller.themePreference},
            showSelectedIcon: false,
            onSelectionChanged: (value) {
              widget.controller.setThemePreference(value.first);
              setState(() {});
            },
          ),
          const SizedBox(height: 20),
          Text('强调色', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in _accentOptions)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: option.color),
                  label: Text(option.label),
                  selected:
                      widget.controller.accentColorValue ==
                      option.color.toARGB32(),
                  selectedColor: option.color.withValues(alpha: 0.18),
                  side: BorderSide(
                    color:
                        widget.controller.accentColorValue ==
                            option.color.toARGB32()
                        ? option.color
                        : theme.colorScheme.outlineVariant,
                  ),
                  onSelected: (_) {
                    widget.controller.setAccentColor(option.color.toARGB32());
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 28),
          Text('自定义背景', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          if (backgroundPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.file(
                File(backgroundPath),
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    await widget.controller.chooseBackgroundImage();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(backgroundPath == null ? '选择图片' : '更换图片'),
                ),
              ),
              if (backgroundPath != null) ...[
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: '移除背景',
                  onPressed: () {
                    widget.controller.clearBackgroundImage();
                    setState(() {});
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          Text('通知', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          Card(
            color: theme.colorScheme.surfaceContainerLowest,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('通知权限'),
                  subtitle: const Text('前往通知开启实况通知以及横幅、声音和震动'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: widget.controller.openCompletionNotificationSettings,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.battery_saver_outlined),
                  title: const Text('忽略电池优化'),
                  subtitle: Text(
                    batteryUnrestricted ? '系统已允许计时器忽略电池优化' : '减少锁屏后被系统中断的可能',
                  ),
                  trailing: Text(batteryUnrestricted ? '已忽略' : '去设置'),
                  onTap: () async {
                    await widget.controller
                        .requestBatteryOptimizationExemption();
                    await _refreshNotificationStatus();
                  },
                ),
              ],
            ),
          ),
          if (widget.controller.webDav case final webDav?) ...[
            const SizedBox(height: 28),
            AnimatedBuilder(
              animation: webDav,
              builder: (context, _) => WebDavSettingsSection(
                serverUrl: webDav.serverUrl,
                username: webDav.username,
                hasSavedPassword: webDav.hasSavedPassword,
                autoSyncEnabled: webDav.syncPreferences.enabled,
                remoteDataUpdatedAt: webDav.remoteDataUpdatedAt,
                lastSyncAt: webDav.syncPreferences.lastSyncedAt,
                autoBackupEnabled: webDav.backupPreferences.enabled,
                backupFrequency: webDav.backupPreferences.frequency,
                lastBackupAt: webDav.backupPreferences.lastBackupAt,
                archives: webDav.backups,
                onSaveConnection: (draft) async {
                  await webDav.saveConnection(
                    url: draft.serverUrl,
                    user: draft.username,
                    password: draft.password,
                  );
                  try {
                    await webDav.refreshRemoteState();
                  } on Object {
                    // Keep the configuration so the user can fix access later.
                  }
                },
                onTestConnection: (draft) => webDav.testConnection(
                  url: draft.serverUrl,
                  user: draft.username,
                  password: draft.password,
                ),
                onSyncNow: () => _syncWebDav(webDav),
                onAutoSyncChanged: webDav.setAutoSync,
                onBackupNow: webDav.createBackup,
                onExportLocalBackup: webDav.exportLocalBackup,
                onAutoBackupChanged: webDav.setAutoBackup,
                onBackupFrequencyChanged: webDav.setBackupFrequency,
                onRestoreArchive: webDav.restoreBackup,
                onDeleteArchive: webDav.deleteBackup,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<bool> _syncWebDav(WebDavSyncManager webDav) async {
    try {
      await webDav.syncNow();
      return true;
    } on WebDavInitialSyncRequired {
      if (!mounted) return false;
      final mode = await showDialog<InitialSyncMode>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('云端已有同步数据'),
          content: const Text('这是当前服务器的首次同步，请选择如何处理本机和云端数据。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, InitialSyncMode.useRemote),
              child: const Text('使用云端'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, InitialSyncMode.useLocal),
              child: const Text('使用本机'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, InitialSyncMode.merge),
              child: const Text('合并数据'),
            ),
          ],
        ),
      );
      if (mode == null) return false;
      await webDav.syncNow(initialMode: mode);
      return true;
    }
  }
}
