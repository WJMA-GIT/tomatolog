import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_platform_service.dart';
import 'sync_backup_models.dart';
import 'webdav_service.dart';

typedef ExportAppData = Future<Map<String, Object?>> Function();
typedef ImportAppData = Future<void> Function(Map<String, Object?> data);
typedef LocalBackupExporter =
    Future<bool> Function(String fileName, Uint8List bytes);

enum InitialSyncMode { merge, useRemote, useLocal }

class WebDavInitialSyncRequired implements Exception {
  const WebDavInitialSyncRequired();

  @override
  String toString() => '云端已有数据，请选择首次同步方式';
}

class WebDavSyncManager extends ChangeNotifier {
  WebDavSyncManager({
    FlutterSecureStorage? secureStorage,
    LocalBackupExporter? localBackupExporter,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _localBackupExporter =
           localBackupExporter ??
           ((fileName, bytes) => AppPlatformService().exportBackupFile(
             fileName: fileName,
             bytes: bytes,
           ));

  static const _syncFile = 'current.json';
  static const _passwordKey = 'tomatolog_webdav_password';
  static const _urlKey = 'webdav_url';
  static const _usernameKey = 'webdav_username';
  static const _deviceKey = 'webdav_device_id';
  static const _baseKey = 'webdav_sync_base';
  static const _syncPreferencesKey = 'webdav_sync_preferences';
  static const _backupPreferencesKey = 'webdav_backup_preferences';
  static const _localChangedAtKey = 'webdav_local_changed_at';

  final FlutterSecureStorage _secureStorage;
  final LocalBackupExporter _localBackupExporter;
  ExportAppData? _exportData;
  ImportAppData? _importData;
  Timer? _autoSyncTimer;
  bool _applyingRemote = false;
  bool _busy = false;

  String serverUrl = '';
  String username = '';
  bool hasSavedPassword = false;
  String deviceId = '';
  SyncPreferences syncPreferences = const SyncPreferences();
  BackupPreferences backupPreferences = const BackupPreferences();
  DateTime? remoteDataUpdatedAt;
  bool hasSyncBase = false;
  DateTime _localChangedAt = DateTime.now().toUtc();
  List<BackupEntry> backups = const [];
  int lastConflictCount = 0;

  bool get configured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      hasSavedPassword;
  bool get busy => _busy;

  void attach({
    required ExportAppData exportData,
    required ImportAppData importData,
  }) {
    _exportData = exportData;
    _importData = importData;
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    serverUrl = preferences.getString(_urlKey) ?? '';
    username = preferences.getString(_usernameKey) ?? '';
    deviceId = preferences.getString(_deviceKey) ?? _newDeviceId();
    hasSyncBase = preferences.containsKey(_baseKey);
    await preferences.setString(_deviceKey, deviceId);
    hasSavedPassword = (await _secureStorage.read(key: _passwordKey)) != null;
    syncPreferences = _decodePreferences(
      preferences.getString(_syncPreferencesKey),
      SyncPreferences.fromJson,
      const SyncPreferences(),
    );
    backupPreferences = _decodePreferences(
      preferences.getString(_backupPreferencesKey),
      BackupPreferences.fromJson,
      const BackupPreferences(),
    );
    _localChangedAt =
        DateTime.tryParse(
          preferences.getString(_localChangedAtKey) ?? '',
        )?.toUtc() ??
        DateTime.now().toUtc();
    notifyListeners();
  }

  Future<void> saveConnection({
    required String url,
    required String user,
    String? password,
  }) async {
    final normalizedUrl = _normalizeUrl(url);
    final normalizedUser = user.trim();
    if (normalizedUser.isEmpty) throw const FormatException('请输入 WebDAV 用户名');
    WebDavClient(
      baseUrl: Uri.parse(normalizedUrl),
      username: normalizedUser,
      password: password ?? '',
    ).close();
    if ((password == null || password.isEmpty) && !hasSavedPassword) {
      throw const FormatException('请输入 WebDAV 密码');
    }
    final endpointChanged =
        normalizedUrl != serverUrl || normalizedUser != username;
    if (password != null && password.isNotEmpty) {
      await _secureStorage.write(key: _passwordKey, value: password);
      hasSavedPassword = true;
    }
    serverUrl = normalizedUrl;
    username = normalizedUser;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_urlKey, serverUrl);
    await preferences.setString(_usernameKey, username);
    if (endpointChanged) {
      await preferences.remove(_baseKey);
      hasSyncBase = false;
      syncPreferences = SyncPreferences(enabled: syncPreferences.enabled);
      remoteDataUpdatedAt = null;
      backups = const [];
      await _saveSyncPreferences(preferences);
    }
    notifyListeners();
  }

  Future<void> testConnection({
    required String url,
    required String user,
    String? password,
  }) async {
    final secret = await _passwordFor(password);
    final client = WebDavClient(
      baseUrl: Uri.parse(_normalizeUrl(url)),
      username: user.trim(),
      password: secret,
    );
    try {
      await client.testConnection();
    } finally {
      client.close();
    }
  }

  Future<void> syncNow({
    InitialSyncMode? initialMode,
  }) => _runExclusive(() async {
    final export = _requireExport();
    final import = _requireImport();
    final preferences = await SharedPreferences.getInstance();
    final client = await _configuredClient();
    try {
      await client.ensureAppDirectories();
      final local = SyncDocument(
        updatedAt: _localChangedAt,
        deviceId: deviceId,
        data: await export(),
      );
      final path = [...client.syncPath, _syncFile];
      WebDavFile? remoteFile;
      try {
        remoteFile = await client.getFile(path);
      } on WebDavException catch (error) {
        if (error.statusCode != 404) rethrow;
      }
      if (remoteFile == null) {
        await client.put(path, utf8.encode(local.encode()), ifNoneMatch: '*');
        await _saveSuccessfulSync(preferences, local, DateTime.now().toUtc());
        return;
      }

      final remote = SyncDocument.decode(utf8.decode(remoteFile.bytes));
      final baseSource = preferences.getString(_baseKey);
      final base = baseSource == null ? null : SyncDocument.decode(baseSource);
      if (base == null && initialMode == null) {
        throw const WebDavInitialSyncRequired();
      }
      if (base == null && initialMode == InitialSyncMode.useRemote) {
        if (!_sameData(local.data, remote.data)) {
          _applyingRemote = true;
          try {
            await import(remote.data);
          } finally {
            _applyingRemote = false;
          }
        }
        await _saveSuccessfulSync(preferences, remote, DateTime.now().toUtc());
        return;
      }
      if (base == null && initialMode == InitialSyncMode.useLocal) {
        final result = SyncDocument(
          updatedAt: DateTime.now().toUtc(),
          deviceId: deviceId,
          data: local.data,
        );
        await client.put(
          path,
          utf8.encode(result.encode()),
          ifMatch: remoteFile.etag,
        );
        await _saveSuccessfulSync(preferences, result, DateTime.now().toUtc());
        return;
      }
      final mergeLocal = base == null
          ? SyncDocument(
              updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
              deviceId: local.deviceId,
              data: local.data,
            )
          : local;
      final merged = SyncMerger.merge(
        local: mergeLocal,
        remote: remote,
        base: base,
      );
      lastConflictCount = merged.conflicts.length;
      final now = DateTime.now().toUtc();
      var result = SyncDocument(
        updatedAt: now,
        deviceId: deviceId,
        data: merged.data,
      );
      if (_sameData(merged.data, remote.data)) {
        result = remote;
      } else {
        await client.put(
          path,
          utf8.encode(result.encode()),
          ifMatch: remoteFile.etag,
        );
      }
      if (!_sameData(local.data, result.data)) {
        _applyingRemote = true;
        try {
          await import(result.data);
        } finally {
          _applyingRemote = false;
        }
      }
      remoteDataUpdatedAt = result.updatedAt.toLocal();
      await _saveSuccessfulSync(preferences, result, now);
    } on WebDavException catch (error) {
      if (error.statusCode == 412) {
        throw const WebDavException('云端数据刚刚发生变化，请重新同步');
      }
      rethrow;
    } finally {
      client.close();
    }
  });

  Future<void> createBackup() => _runExclusive(() async {
    final snapshot = BackupSnapshot(
      createdAt: DateTime.now().toUtc(),
      data: await _requireExport()(),
    );
    final client = await _configuredClient();
    try {
      await client.ensureAppDirectories();
      await client.put(
        [...client.backupsPath, snapshot.fileName],
        utf8.encode(snapshot.encode()),
        ifNoneMatch: '*',
      );
      backupPreferences = BackupPreferences(
        enabled: backupPreferences.enabled,
        frequency: backupPreferences.frequency,
        lastBackupAt: snapshot.createdAt.toLocal(),
      );
      final preferences = await SharedPreferences.getInstance();
      await _saveBackupPreferences(preferences);
      await _refreshBackupsWith(client);
    } finally {
      client.close();
    }
  });

  Future<bool> exportLocalBackup() => _runExclusive(() async {
    final snapshot = BackupSnapshot(
      createdAt: DateTime.now().toUtc(),
      data: await _requireExport()(),
    );
    return _localBackupExporter(
      snapshot.fileName,
      Uint8List.fromList(utf8.encode(snapshot.encode())),
    );
  });

  Future<void> refreshRemoteState() => _runExclusive(() async {
    final client = await _configuredClient();
    try {
      await client.ensureAppDirectories();
      try {
        final file = await client.getFile([...client.syncPath, _syncFile]);
        remoteDataUpdatedAt = SyncDocument.decode(
          utf8.decode(file.bytes),
        ).updatedAt.toLocal();
      } on WebDavException catch (error) {
        if (error.statusCode != 404) rethrow;
        remoteDataUpdatedAt = null;
      }
      await _refreshBackupsWith(client);
    } finally {
      client.close();
    }
  });

  Future<void> restoreBackup(BackupEntry entry) => _runExclusive(() async {
    final client = await _configuredClient();
    try {
      final bytes = await client.get([...client.backupsPath, entry.fileName]);
      final snapshot = BackupSnapshot.decode(utf8.decode(bytes));
      await _requireImport()(snapshot.data);
      _localChangedAt = DateTime.now().toUtc();
      await _saveLocalChangedAt();
    } finally {
      client.close();
    }
  });

  Future<void> deleteBackup(BackupEntry entry) => _runExclusive(() async {
    final client = await _configuredClient();
    try {
      await client.delete([...client.backupsPath, entry.fileName]);
      await _refreshBackupsWith(client);
    } finally {
      client.close();
    }
  });

  Future<void> setAutoSync(bool enabled) async {
    syncPreferences = SyncPreferences(
      enabled: enabled,
      lastSyncedAt: syncPreferences.lastSyncedAt,
    );
    await _saveSyncPreferences(await SharedPreferences.getInstance());
    notifyListeners();
  }

  Future<void> setAutoBackup(bool enabled) async {
    backupPreferences = BackupPreferences(
      enabled: enabled,
      frequency: backupPreferences.frequency,
      lastBackupAt: backupPreferences.lastBackupAt,
    );
    await _saveBackupPreferences(await SharedPreferences.getInstance());
    notifyListeners();
    if (enabled && configured && _backupDue()) await createBackup();
  }

  Future<void> setBackupFrequency(BackupFrequency frequency) async {
    backupPreferences = BackupPreferences(
      enabled: backupPreferences.enabled,
      frequency: frequency,
      lastBackupAt: backupPreferences.lastBackupAt,
    );
    await _saveBackupPreferences(await SharedPreferences.getInstance());
    notifyListeners();
  }

  void markLocalChanged() {
    if (_applyingRemote) return;
    _localChangedAt = DateTime.now().toUtc();
    unawaited(_saveLocalChangedAt());
    if (!syncPreferences.enabled || !configured) return;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(const Duration(seconds: 3), () {
      unawaited(syncNow().catchError((Object _) {}));
    });
  }

  Future<void> runAutomaticTasks() async {
    if (!configured) return;
    if (backupPreferences.enabled && _backupDue()) {
      try {
        await createBackup();
      } on Object {
        // Automatic work is retried next time the app opens.
      }
    }
    if (syncPreferences.enabled) {
      try {
        await syncNow();
      } on Object {
        // Manual actions surface errors; automatic work stays non-blocking.
      }
    }
  }

  bool _backupDue() {
    final last = backupPreferences.lastBackupAt;
    if (last == null) return true;
    final interval = backupPreferences.frequency == BackupFrequency.daily
        ? const Duration(days: 1)
        : const Duration(days: 7);
    return DateTime.now().difference(last) >= interval;
  }

  Future<void> _refreshBackupsWith(WebDavClient client) async {
    final entries = await client.list(client.backupsPath);
    backups =
        entries
            .where(
              (entry) => !entry.isCollection && entry.name.endsWith('.json'),
            )
            .map((entry) {
              final namedTime = _backupTimeFromName(entry.name);
              return BackupEntry(
                fileName: entry.name,
                createdAt: namedTime.millisecondsSinceEpoch == 0
                    ? entry.modifiedAt ?? namedTime
                    : namedTime,
                sizeBytes: entry.size ?? 0,
              );
            })
            .toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    notifyListeners();
  }

  Future<WebDavClient> _configuredClient() async {
    if (!configured) throw StateError('请先配置 WebDAV');
    return WebDavClient(
      baseUrl: Uri.parse(serverUrl),
      username: username,
      password: await _passwordFor(null),
    );
  }

  Future<String> _passwordFor(String? password) async {
    if (password != null && password.isNotEmpty) return password;
    final saved = await _secureStorage.read(key: _passwordKey);
    if (saved == null) throw StateError('请填写 WebDAV 密码');
    return saved;
  }

  ExportAppData _requireExport() =>
      _exportData ?? (throw StateError('WebDAV 尚未连接应用数据'));
  ImportAppData _requireImport() =>
      _importData ?? (throw StateError('WebDAV 尚未连接应用数据'));

  Future<void> _saveSuccessfulSync(
    SharedPreferences preferences,
    SyncDocument document,
    DateTime syncedAt,
  ) async {
    await preferences.setString(_baseKey, document.encode());
    hasSyncBase = true;
    _localChangedAt = document.updatedAt;
    await preferences.setString(
      _localChangedAtKey,
      _localChangedAt.toIso8601String(),
    );
    syncPreferences = SyncPreferences(
      enabled: syncPreferences.enabled,
      lastSyncedAt: syncedAt.toLocal(),
    );
    remoteDataUpdatedAt = document.updatedAt.toLocal();
    await _saveSyncPreferences(preferences);
    notifyListeners();
  }

  Future<void> _saveSyncPreferences(SharedPreferences preferences) =>
      preferences.setString(
        _syncPreferencesKey,
        jsonEncode(syncPreferences.toJson()),
      );
  Future<void> _saveBackupPreferences(SharedPreferences preferences) =>
      preferences.setString(
        _backupPreferencesKey,
        jsonEncode(backupPreferences.toJson()),
      );
  Future<void> _saveLocalChangedAt() async =>
      (await SharedPreferences.getInstance()).setString(
        _localChangedAtKey,
        _localChangedAt.toIso8601String(),
      );

  Future<T> _runExclusive<T>(Future<T> Function() action) async {
    if (_busy) throw StateError('另一项 WebDAV 操作正在进行');
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  static T _decodePreferences<T>(
    String? source,
    T Function(Map<String, Object?> json) decode,
    T fallback,
  ) {
    if (source == null) return fallback;
    try {
      final value = jsonDecode(source);
      return value is Map ? decode(value.cast<String, Object?>()) : fallback;
    } on Object {
      return fallback;
    }
  }

  static String _normalizeUrl(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException('请输入正确的 HTTP(S) WebDAV 地址');
    }
    return uri
        .replace(path: uri.path.endsWith('/') ? uri.path : '${uri.path}/')
        .toString();
  }

  static bool _sameData(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) => jsonEncode(left) == jsonEncode(right);

  static DateTime _backupTimeFromName(String name) {
    final match = RegExp(
      r'^backup-(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})',
    ).firstMatch(name);
    if (match == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.utc(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    ).toLocal();
  }

  static String _newDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return '${DateTime.now().microsecondsSinceEpoch}-${base64UrlEncode(bytes)}';
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}
