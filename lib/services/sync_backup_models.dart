import 'dart:convert';

import '../models/daily_plan.dart';
import '../models/focus_category.dart';
import '../models/time_log.dart';

/// Versioned, self-contained app data exchanged through WebDAV.
class SyncDocument {
  const SyncDocument({
    required this.updatedAt,
    required this.deviceId,
    required this.data,
  });

  static const schemaVersion = 1;

  final DateTime updatedAt;
  final String deviceId;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'data': data,
  };

  String encode() => jsonEncode(toJson());

  factory SyncDocument.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('Invalid sync document');
    return SyncDocument.fromJson(decoded.cast<String, Object?>());
  }

  factory SyncDocument.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported sync schema');
    }
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    final deviceId = json['deviceId'];
    final data = json['data'];
    if (updatedAt == null ||
        deviceId is! String ||
        deviceId.isEmpty ||
        data is! Map ||
        !_isJsonValue(data)) {
      throw const FormatException('Corrupt sync document');
    }
    _validateAppData(data);
    return SyncDocument(
      updatedAt: updatedAt.toUtc(),
      deviceId: deviceId,
      data: _copyMap(data),
    );
  }
}

enum SyncChoice { local, remote }

class SyncConflict {
  const SyncConflict({required this.path, required this.chosen});

  final String path;
  final SyncChoice chosen;
}

class SyncMergeResult {
  const SyncMergeResult({required this.data, required this.conflicts});

  final Map<String, Object?> data;
  final List<SyncConflict> conflicts;
}

/// Three-way merge. [base] is the document saved after the previous sync.
/// A missing base means first sync; both sides are retained where possible.
class SyncMerger {
  const SyncMerger._();

  static SyncMergeResult merge({
    required SyncDocument local,
    required SyncDocument remote,
    SyncDocument? base,
  }) {
    final conflicts = <SyncConflict>[];
    final prefer = local.updatedAt.isAfter(remote.updatedAt)
        ? SyncChoice.local
        : SyncChoice.remote;
    final data = _mergeMap(
      local.data,
      remote.data,
      base?.data,
      '',
      prefer,
      conflicts,
    );
    _repairReferences(data);
    return SyncMergeResult(data: data, conflicts: List.unmodifiable(conflicts));
  }
}

/// An immutable backup file. Its payload is never merged.
class BackupSnapshot {
  const BackupSnapshot({required this.createdAt, required this.data});

  static const schemaVersion = 1;

  final DateTime createdAt;
  final Map<String, Object?> data;

  String get fileName =>
      'backup-${createdAt.toUtc().toIso8601String().replaceAll(':', '-')}.json';

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'data': data,
  };

  String encode() => jsonEncode(toJson());

  factory BackupSnapshot.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('Invalid backup');
    final json = decoded.cast<String, Object?>();
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported backup schema');
    }
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final data = json['data'];
    if (createdAt == null || data is! Map || !_isJsonValue(data)) {
      throw const FormatException('Corrupt backup');
    }
    _validateAppData(data);
    return BackupSnapshot(createdAt: createdAt.toUtc(), data: _copyMap(data));
  }
}

class BackupEntry {
  const BackupEntry({
    required this.fileName,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String fileName;
  final DateTime createdAt;
  final int sizeBytes;
}

/// Sync and backup automation are intentionally stored separately.
class SyncPreferences {
  const SyncPreferences({this.enabled = false, this.lastSyncedAt});

  final bool enabled;
  final DateTime? lastSyncedAt;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
  };

  factory SyncPreferences.fromJson(Map<String, Object?> json) =>
      SyncPreferences(
        enabled: json['enabled'] as bool? ?? false,
        lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] as String? ?? ''),
      );
}

enum BackupFrequency { daily, weekly }

class BackupPreferences {
  const BackupPreferences({
    this.enabled = false,
    this.frequency = BackupFrequency.daily,
    this.lastBackupAt,
  });

  final bool enabled;
  final BackupFrequency frequency;
  final DateTime? lastBackupAt;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'frequency': frequency.name,
    'lastBackupAt': lastBackupAt?.toUtc().toIso8601String(),
  };

  factory BackupPreferences.fromJson(Map<String, Object?> json) =>
      BackupPreferences(
        enabled: json['enabled'] as bool? ?? false,
        frequency: BackupFrequency.values.firstWhere(
          (value) => value.name == json['frequency'],
          orElse: () => BackupFrequency.daily,
        ),
        lastBackupAt: DateTime.tryParse(json['lastBackupAt'] as String? ?? ''),
      );
}

const _missing = Object();

Map<String, Object?> _mergeMap(
  Map<String, Object?> local,
  Map<String, Object?> remote,
  Map<String, Object?>? base,
  String path,
  SyncChoice prefer,
  List<SyncConflict> conflicts,
) {
  final result = <String, Object?>{};
  final keys = {...local.keys, ...remote.keys, ...?base?.keys};
  for (final key in keys) {
    final childPath = path.isEmpty ? key : '$path.$key';
    final localValue = local.containsKey(key) ? local[key] : _missing;
    final remoteValue = remote.containsKey(key) ? remote[key] : _missing;
    final baseValue = base?.containsKey(key) == true ? base![key] : _missing;
    final value = _mergeValue(
      localValue,
      remoteValue,
      baseValue,
      childPath,
      prefer,
      conflicts,
    );
    if (!identical(value, _missing)) result[key] = value;
  }
  return result;
}

Object? _mergeValue(
  Object? local,
  Object? remote,
  Object? base,
  String path,
  SyncChoice prefer,
  List<SyncConflict> conflicts,
) {
  if (_deepEquals(local, remote)) return _copyValue(local);
  if (_deepEquals(local, base)) return _copyValue(remote);
  if (_deepEquals(remote, base)) return _copyValue(local);

  if (local is Map && remote is Map) {
    return _mergeMap(
      local.cast<String, Object?>(),
      remote.cast<String, Object?>(),
      base is Map ? base.cast<String, Object?>() : null,
      path,
      prefer,
      conflicts,
    );
  }
  if (_isIdList(local) && _isIdList(remote)) {
    return _mergeIdList(
      local as List,
      remote as List,
      base is List ? base : const [],
      path,
      prefer,
      conflicts,
    );
  }
  if (path.endsWith('.completedDates') && local is List && remote is List) {
    return _mergeStringSet(local, remote, base is List ? base : const []);
  }

  conflicts.add(SyncConflict(path: path, chosen: prefer));
  return _copyValue(prefer == SyncChoice.local ? local : remote);
}

List<Object?> _mergeIdList(
  List local,
  List remote,
  List base,
  String path,
  SyncChoice prefer,
  List<SyncConflict> conflicts,
) {
  Map<String, Map<String, Object?>> index(List values) => {
    for (final value in values)
      (value as Map)['id'] as String: value.cast<String, Object?>(),
  };
  final localById = index(local);
  final remoteById = index(remote);
  final baseById = _isIdList(base)
      ? index(base)
      : <String, Map<String, Object?>>{};
  final ids = {...localById.keys, ...remoteById.keys, ...baseById.keys}.toList()
    ..sort();
  final result = <Object?>[];
  for (final id in ids) {
    final value = _mergeValue(
      localById[id] ?? _missing,
      remoteById[id] ?? _missing,
      baseById[id] ?? _missing,
      '$path[$id]',
      prefer,
      conflicts,
    );
    if (!identical(value, _missing)) result.add(value);
  }
  return result;
}

List<String> _mergeStringSet(List local, List remote, List base) {
  final localSet = local.cast<String>().toSet();
  final remoteSet = remote.cast<String>().toSet();
  final baseSet = base.cast<String>().toSet();
  return {
    ...baseSet.where(localSet.contains).where(remoteSet.contains),
    ...localSet.difference(baseSet),
    ...remoteSet.difference(baseSet),
  }.toList()..sort();
}

void _repairReferences(Map<String, Object?> data) {
  final categories = (data['categories'] as List?)?.whereType<Map>().toList();
  if (categories == null) return;
  final ids = categories.map((item) => item['id']).whereType<String>().toSet();
  for (final category in categories) {
    if (category['parentId'] != null && !ids.contains(category['parentId'])) {
      category['parentId'] = null;
    }
  }
  data['categories'] = categories;
  for (final key in const ['logs', 'plans']) {
    final values = data[key];
    if (values is List) {
      data[key] = values
          .whereType<Map>()
          .where((item) => ids.contains(item['categoryId']))
          .toList();
    }
  }
  if (!ids.contains(data['selectedCategoryId'])) {
    final active = categories.where((item) => item['isArchived'] != true);
    data['selectedCategoryId'] = active.isEmpty ? null : active.first['id'];
  }
}

void _validateAppData(Map data) {
  for (final key in const ['categories', 'logs', 'plans']) {
    final value = data[key];
    if (value != null && !_isIdList(value)) {
      throw FormatException('Invalid $key');
    }
  }
  try {
    for (final item in (data['categories'] as List?) ?? const []) {
      FocusCategory.fromJson((item as Map).cast<String, Object?>());
    }
    for (final item in (data['logs'] as List?) ?? const []) {
      TimeLog.fromJson((item as Map).cast<String, Object?>());
    }
    for (final item in (data['plans'] as List?) ?? const []) {
      DailyPlan.fromJson((item as Map).cast<String, Object?>());
    }
  } on Object {
    throw const FormatException('Corrupt app data');
  }
}

bool _isIdList(Object? value) =>
    value is List &&
    value.every(
      (item) => item is Map && item['id'] is String && item['id'] != '',
    );

bool _isJsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return true;
  }
  if (value is List) return value.every(_isJsonValue);
  if (value is Map) {
    return value.keys.every((key) => key is String) &&
        value.values.every(_isJsonValue);
  }
  return false;
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (index) => index,
        ).every((index) => _deepEquals(a[index], b[index]));
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && _deepEquals(a[key], b[key]),
        );
  }
  return a == b;
}

Map<String, Object?> _copyMap(Map source) =>
    source.map((key, value) => MapEntry(key as String, _copyValue(value)));

Object? _copyValue(Object? value) {
  if (identical(value, _missing)) return _missing;
  if (value is Map) return _copyMap(value);
  if (value is List) return value.map(_copyValue).toList();
  return value;
}
