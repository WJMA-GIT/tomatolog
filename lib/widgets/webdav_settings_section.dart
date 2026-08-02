import 'dart:async';

import 'package:flutter/material.dart';

import '../services/sync_backup_models.dart';

class WebDavConnectionDraft {
  const WebDavConnectionDraft({
    required this.serverUrl,
    required this.username,
    this.password,
  });

  final String serverUrl;
  final String username;
  final String? password;
}

class WebDavSettingsSection extends StatefulWidget {
  const WebDavSettingsSection({
    super.key,
    required this.serverUrl,
    required this.username,
    required this.hasSavedPassword,
    required this.autoSyncEnabled,
    required this.remoteDataUpdatedAt,
    required this.autoBackupEnabled,
    required this.backupFrequency,
    required this.archives,
    required this.onSaveConnection,
    required this.onTestConnection,
    required this.onSyncNow,
    required this.onAutoSyncChanged,
    required this.onBackupNow,
    required this.onExportLocalBackup,
    required this.onAutoBackupChanged,
    required this.onBackupFrequencyChanged,
    required this.onRestoreArchive,
    required this.onDeleteArchive,
    this.lastSyncAt,
    this.lastBackupAt,
  });

  final String serverUrl;
  final String username;
  final bool hasSavedPassword;
  final bool autoSyncEnabled;
  final DateTime? remoteDataUpdatedAt;
  final DateTime? lastSyncAt;
  final bool autoBackupEnabled;
  final BackupFrequency backupFrequency;
  final DateTime? lastBackupAt;
  final List<BackupEntry> archives;
  final Future<void> Function(WebDavConnectionDraft draft) onSaveConnection;
  final Future<void> Function(WebDavConnectionDraft draft) onTestConnection;
  final Future<bool> Function() onSyncNow;
  final Future<void> Function(bool enabled) onAutoSyncChanged;
  final Future<void> Function() onBackupNow;
  final Future<bool> Function() onExportLocalBackup;
  final Future<void> Function(bool enabled) onAutoBackupChanged;
  final Future<void> Function(BackupFrequency frequency)
  onBackupFrequencyChanged;
  final Future<void> Function(BackupEntry archive) onRestoreArchive;
  final Future<void> Function(BackupEntry archive) onDeleteArchive;

  @override
  State<WebDavSettingsSection> createState() => _WebDavSettingsSectionState();
}

class _WebDavSettingsSectionState extends State<WebDavSettingsSection> {
  bool _busy = false;
  OverlayEntry? _toastEntry;
  Timer? _toastTimer;

  bool get _configured =>
      widget.serverUrl.trim().isNotEmpty && widget.username.trim().isNotEmpty;

  Future<void> _run<T>(
    Future<T> Function() action, {
    String? successMessage,
    bool Function(T result)? succeeded,
    String? cancelledMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      if (succeeded != null && !succeeded(result)) {
        if (cancelledMessage != null) _showToast(cancelledMessage);
      } else if (successMessage != null) {
        _showToast(successMessage);
      }
    } catch (error) {
      if (mounted) _showToast('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    final overlay = Overlay.of(context, rootOverlay: true);
    _toastEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: SafeArea(
          minimum: const EdgeInsets.only(bottom: 80),
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        message,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_toastEntry!);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WebDAV', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(
          color: theme.colorScheme.surfaceContainerLowest,
          child: ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(_configured ? widget.username : '配置 WebDAV'),
            subtitle: Text(
              _configured ? widget.serverUrl : '连接你的 WebDAV 服务器',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _busy ? null : _showConnectionDialog,
          ),
        ),
        const SizedBox(height: 20),
        Text('同步', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        Card(
          color: theme.colorScheme.surfaceContainerLowest,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: const Text('立即同步'),
                subtitle: Text(
                  '${_timeLabel('最近同步', widget.lastSyncAt)}\n'
                  '${widget.remoteDataUpdatedAt == null ? '云端暂无同步数据' : '云端数据：${_formatDateTime(widget.remoteDataUpdatedAt!)}'}',
                ),
                trailing: _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right_rounded),
                enabled: _configured && !_busy,
                onTap: () => _run<bool>(
                  widget.onSyncNow,
                  successMessage: '同步完成',
                  succeeded: (completed) => completed,
                  cancelledMessage: '同步已取消',
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.sync_lock_rounded),
                title: const Text('自动同步'),
                subtitle: const Text('数据变化后自动与 WebDAV 合并'),
                value: widget.autoSyncEnabled,
                onChanged: _configured && !_busy
                    ? (value) => _run(() => widget.onAutoSyncChanged(value))
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('备份', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        Card(
          color: theme.colorScheme.surfaceContainerLowest,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('立即云端备份'),
                subtitle: Text(_timeLabel('最近备份', widget.lastBackupAt)),
                trailing: const Icon(Icons.chevron_right_rounded),
                enabled: _configured && !_busy,
                onTap: () => _run(widget.onBackupNow, successMessage: '备份完成'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.history_rounded),
                title: const Text('自动备份'),
                subtitle: const Text('按设定频率生成独立存档'),
                value: widget.autoBackupEnabled,
                onChanged: _configured && !_busy
                    ? (value) => _run(() => widget.onAutoBackupChanged(value))
                    : null,
              ),
              if (widget.autoBackupEnabled) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.event_repeat_rounded),
                  title: const Text('备份频率'),
                  trailing: DropdownButton<BackupFrequency>(
                    value: widget.backupFrequency,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: BackupFrequency.daily,
                        child: Text('每天'),
                      ),
                      DropdownMenuItem(
                        value: BackupFrequency.weekly,
                        child: Text('每周'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              _run(
                                () => widget.onBackupFrequencyChanged(value),
                              );
                            }
                          },
                  ),
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('导出本地备份'),
                subtitle: const Text('选择手机本地位置保存完整存档'),
                trailing: const Icon(Icons.chevron_right_rounded),
                enabled: !_busy,
                onTap: () => _run<bool>(
                  widget.onExportLocalBackup,
                  successMessage: '本地备份已导出',
                  succeeded: (exported) => exported,
                  cancelledMessage: '备份已取消',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Text('备份存档', style: theme.textTheme.titleMedium)),
            Text('${widget.archives.length} 份'),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          color: theme.colorScheme.surfaceContainerLowest,
          child: widget.archives.isEmpty
              ? const ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('暂无备份'),
                  subtitle: Text('手动备份或开启自动备份后，存档会显示在这里'),
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < widget.archives.length;
                      index++
                    ) ...[
                      _ArchiveTile(
                        archive: widget.archives[index],
                        enabled: !_busy,
                        onRestore: () =>
                            _confirmRestore(widget.archives[index]),
                        onDelete: () => _confirmDelete(widget.archives[index]),
                      ),
                      if (index != widget.archives.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _showConnectionDialog() async {
    final serverController = TextEditingController(text: widget.serverUrl);
    final usernameController = TextEditingController(text: widget.username);
    final passwordController = TextEditingController();
    var obscurePassword = true;
    final draft = await showDialog<WebDavConnectionDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('WebDAV 配置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: serverController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://example.com/dav/',
                    prefixIcon: Icon(Icons.language_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: widget.hasSavedPassword ? '留空则使用已保存密码' : null,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: obscurePassword ? '显示密码' : '隐藏密码',
                      onPressed: () => setDialogState(
                        () => obscurePassword = !obscurePassword,
                      ),
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                final value = _connectionDraft(
                  serverController,
                  usernameController,
                  passwordController,
                );
                if (value == null) {
                  _showDialogError(dialogContext, '请填写服务器地址和用户名');
                  return;
                }
                await _run(
                  () => widget.onTestConnection(value),
                  successMessage: '连接成功',
                );
              },
              child: const Text('测试连接'),
            ),
            FilledButton(
              onPressed: () {
                final value = _connectionDraft(
                  serverController,
                  usernameController,
                  passwordController,
                );
                if (value == null) {
                  _showDialogError(dialogContext, '请填写服务器地址和用户名');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    serverController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    if (draft != null) {
      await _run(
        () => widget.onSaveConnection(draft),
        successMessage: 'WebDAV 配置已保存',
      );
    }
  }

  WebDavConnectionDraft? _connectionDraft(
    TextEditingController server,
    TextEditingController username,
    TextEditingController password,
  ) {
    final url = server.text.trim();
    final user = username.text.trim();
    if (url.isEmpty || user.isEmpty) return null;
    final secret = password.text;
    return WebDavConnectionDraft(
      serverUrl: url,
      username: user,
      password: secret.isEmpty ? null : secret,
    );
  }

  void _showDialogError(BuildContext context, String message) {
    _showToast(message);
  }

  Future<void> _confirmRestore(BackupEntry archive) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复这份备份？'),
        content: Text('将用 ${_formatDateTime(archive.createdAt)} 的存档替换本地数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(
        () => widget.onRestoreArchive(archive),
        successMessage: '备份已恢复',
      );
    }
  }

  Future<void> _confirmDelete(BackupEntry archive) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这份备份？'),
        content: Text('${_formatDateTime(archive.createdAt)} 的存档将永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(
        () => widget.onDeleteArchive(archive),
        successMessage: '备份已删除',
      );
    }
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({
    required this.archive,
    required this.enabled,
    required this.onRestore,
    required this.onDelete,
  });

  final BackupEntry archive;
  final bool enabled;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(_formatDateTime(archive.createdAt)),
      subtitle: Text(_formatBytes(archive.sizeBytes)),
      trailing: PopupMenuButton<String>(
        enabled: enabled,
        tooltip: '管理备份',
        onSelected: (value) => value == 'restore' ? onRestore() : onDelete(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'restore', child: Text('恢复')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }
}

String _timeLabel(String prefix, DateTime? time) =>
    time == null ? '$prefix：暂无记录' : '$prefix：${_formatDateTime(time)}';

String _formatDateTime(DateTime time) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${twoDigits(time.month)}-${twoDigits(time.day)} '
      '${twoDigits(time.hour)}:${twoDigits(time.minute)}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
