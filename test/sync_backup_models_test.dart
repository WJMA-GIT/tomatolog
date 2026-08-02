import 'package:flutter_test/flutter_test.dart';
import 'package:tomatolog/services/sync_backup_models.dart';

void main() {
  SyncDocument document(
    Map<String, Object?> data, {
    int minute = 0,
    String device = 'device',
  }) => SyncDocument(
    updatedAt: DateTime.utc(2026, 8, 2, 10, minute),
    deviceId: device,
    data: data,
  );

  Map<String, Object?> category(String id, {String? parentId}) => {
    'id': id,
    'name': id,
    'colorValue': 1,
    'iconKey': 'work',
    'parentId': parentId,
    'isArchived': false,
  };

  Map<String, Object?> log(String id, String categoryId) => {
    'id': id,
    'categoryId': categoryId,
    'startedAt': '2026-08-02T10:00:00.000Z',
    'endedAt': '2026-08-02T10:25:00.000Z',
    'plannedSeconds': 1500,
    'actualSeconds': 1500,
    'status': 'completed',
    'note': null,
  };

  Map<String, Object?> plan(String id, String categoryId) => {
    'id': id,
    'startDate': '2026-08-01T00:00:00.000Z',
    'endDate': '2026-08-31T00:00:00.000Z',
    'categoryId': categoryId,
    'plannedMinutes': 25,
    'completedDates': <String>[],
  };

  test('round trips complete and future app payloads', () {
    final original = document({
      'categories': [category('work')],
      'logs': <Object?>[],
      'plans': <Object?>[],
      'backgroundImage': {'mimeType': 'image/png', 'base64': 'AA=='},
      'futureSetting': {'nested': true},
    });

    final restored = SyncDocument.decode(original.encode());

    expect(restored.data, original.data);
    expect(restored.updatedAt, original.updatedAt);
  });

  test('rejects unknown schemas and damaged collection data', () {
    expect(
      () => SyncDocument.decode('{"schemaVersion":2}'),
      throwsFormatException,
    );
    expect(
      () => SyncDocument.decode(
        '{"schemaVersion":1,"updatedAt":"2026-08-02T00:00:00Z",'
        '"deviceId":"a","data":{"categories":[{"name":"bad"}]}}',
      ),
      throwsFormatException,
    );
  });

  test('three-way merge propagates deletions and keeps new remote records', () {
    final base = document({
      'categories': [category('work'), category('child', parentId: 'work')],
      'logs': [log('old-log', 'child')],
      'plans': <Object?>[],
      'selectedCategoryId': 'child',
    });
    final local = document({
      'categories': <Object?>[],
      'logs': <Object?>[],
      'plans': <Object?>[],
      'selectedCategoryId': null,
    }, minute: 2);
    final remote = document({
      ...base.data,
      'logs': [...(base.data['logs']! as List), log('remote-log', 'child')],
    }, minute: 1);

    final result = SyncMerger.merge(local: local, remote: remote, base: base);

    // The unchanged remote category subtree accepts the local deletion;
    // its newly uploaded dangling log is removed as invalid app data.
    expect(result.data['categories'], isEmpty);
    expect(result.data['logs'], isEmpty);
    expect(result.conflicts, isEmpty);
  });

  test('merges independent edits and reports same-field conflicts', () {
    final base = document({
      'categories': [category('work')],
      'logs': <Object?>[],
      'plans': [plan('plan', 'work')],
      'accentColorValue': 1,
    });
    final local = document(
      {
        ...base.data,
        'plans': [
          {
            ...(base.data['plans']! as List).single as Map,
            'completedDates': ['2026-08-01'],
          },
        ],
        'accentColorValue': 2,
      },
      minute: 1,
      device: 'local',
    );
    final remote = document(
      {
        ...base.data,
        'plans': [
          {
            ...(base.data['plans']! as List).single as Map,
            'completedDates': ['2026-08-02'],
          },
        ],
        'accentColorValue': 3,
      },
      minute: 2,
      device: 'remote',
    );

    final result = SyncMerger.merge(local: local, remote: remote, base: base);

    final mergedPlan = (result.data['plans']! as List).single as Map;
    expect(mergedPlan['completedDates'], ['2026-08-01', '2026-08-02']);
    expect(result.data['accentColorValue'], 3);
    expect(result.conflicts.single.path, 'accentColorValue');
    expect(result.conflicts.single.chosen, SyncChoice.remote);
  });

  test('backup is an immutable timestamped snapshot', () {
    final backup = BackupSnapshot(
      createdAt: DateTime.utc(2026, 8, 2, 10, 5, 6),
      data: {
        'categories': [category('work')],
        'logs': <Object?>[],
        'plans': <Object?>[],
      },
    );

    expect(backup.fileName, 'backup-2026-08-02T10-05-06.000Z.json');
    expect(BackupSnapshot.decode(backup.encode()).data, backup.data);
  });

  test('sync and backup automation states are independent', () {
    final syncedAt = DateTime.utc(2026, 8, 2, 10);
    const backup = BackupPreferences(
      enabled: true,
      frequency: BackupFrequency.weekly,
    );
    final sync = SyncPreferences(enabled: false, lastSyncedAt: syncedAt);

    expect(sync.enabled, isFalse);
    expect(sync.lastSyncedAt, syncedAt);
    expect(backup.enabled, isTrue);
    expect(backup.frequency, BackupFrequency.weekly);
    expect(backup.lastBackupAt, isNull);
  });
}
