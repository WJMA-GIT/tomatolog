import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tomatolog/services/sync_backup_models.dart';
import 'package:tomatolog/services/webdav_sync_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'exports a versioned local backup and preserves picker cancellation',
    () async {
      String? exportedName;
      List<int>? exportedBytes;
      var shouldSave = false;
      final manager =
          WebDavSyncManager(
            localBackupExporter: (fileName, bytes) async {
              exportedName = fileName;
              exportedBytes = bytes;
              return shouldSave;
            },
          )..attach(
            exportData: () async => _appData(['work']),
            importData: (_) async {},
          );
      addTearDown(manager.dispose);

      expect(await manager.exportLocalBackup(), isFalse);
      expect(exportedName, startsWith('backup-'));
      expect(
        BackupSnapshot.decode(utf8.decode(exportedBytes!)).data,
        _appData(['work']),
      );

      shouldSave = true;
      expect(await manager.exportLocalBackup(), isTrue);
    },
  );

  test(
    'syncs remote changes and manages immutable backups separately',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final files = <String, List<int>>{};
      final etags = <String, String>{};
      var revision = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final path = request.uri.path;
        if (request.method == 'MKCOL') {
          request.response.statusCode = HttpStatus.created;
        } else if (request.method == 'PROPFIND' &&
            request.headers.value('Depth') == '1') {
          request.response.statusCode = 207;
          request.response.write(_backupListing(files, server.port));
        } else if (request.method == 'PROPFIND') {
          request.response.statusCode = 207;
        } else if (request.method == 'GET') {
          final bytes = files[path];
          if (bytes == null) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.headers.set(HttpHeaders.etagHeader, etags[path]!);
            request.response.add(bytes);
          }
        } else if (request.method == 'PUT') {
          final ifNoneMatch = request.headers.value(
            HttpHeaders.ifNoneMatchHeader,
          );
          final ifMatch = request.headers.value(HttpHeaders.ifMatchHeader);
          if ((ifNoneMatch == '*' && files.containsKey(path)) ||
              (ifMatch != null && ifMatch != etags[path])) {
            request.response.statusCode = HttpStatus.preconditionFailed;
          } else {
            files[path] = await request.fold<List<int>>(<int>[], (all, bytes) {
              all.addAll(bytes);
              return all;
            });
            etags[path] = '"${++revision}"';
            request.response.statusCode = HttpStatus.created;
          }
        } else if (request.method == 'DELETE') {
          files.remove(path);
          etags.remove(path);
          request.response.statusCode = HttpStatus.noContent;
        }
        await request.response.close();
      });

      var local = _appData(['work']);
      final imported = <Map<String, Object?>>[];
      final manager = WebDavSyncManager()
        ..attach(
          exportData: () async => local,
          importData: (data) async {
            local = data;
            imported.add(data);
          },
        );
      addTearDown(() async {
        manager.dispose();
        await server.close(force: true);
      });
      await manager.load();
      await manager.saveConnection(
        url: 'http://127.0.0.1:${server.port}/dav/',
        user: 'tomato',
        password: 'secret',
      );

      await manager.syncNow();
      final syncPath = '/dav/tomatolog/sync/current.json';
      expect(files, contains(syncPath));
      expect(manager.syncPreferences.lastSyncedAt, isNotNull);

      final remote = SyncDocument(
        updatedAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        deviceId: 'other-device',
        data: _appData(['work', 'study']),
      );
      files[syncPath] = utf8.encode(remote.encode());
      etags[syncPath] = '"${++revision}"';
      await manager.syncNow();
      expect(imported, isNotEmpty);
      expect((local['categories'] as List), hasLength(2));

      await manager.createBackup();
      expect(manager.backups, hasLength(1));
      expect(manager.backupPreferences.lastBackupAt, isNotNull);
      final backup = manager.backups.single;

      local = _appData(['work']);
      await manager.restoreBackup(backup);
      expect((local['categories'] as List), hasLength(2));
      await manager.deleteBackup(backup);
      expect(manager.backups, isEmpty);

      await manager.saveConnection(
        url: 'http://127.0.0.1:${server.port}/other/',
        user: 'tomato',
      );
      final otherSyncPath = '/other/tomatolog/sync/current.json';
      files[otherSyncPath] = utf8.encode(remote.encode());
      etags[otherSyncPath] = '"${++revision}"';
      await expectLater(
        manager.syncNow(),
        throwsA(isA<WebDavInitialSyncRequired>()),
      );
      await manager.syncNow(initialMode: InitialSyncMode.useRemote);
      expect((local['categories'] as List), hasLength(2));
    },
  );
}

Map<String, Object?> _appData(List<String> ids) => {
  'categories': [
    for (final id in ids)
      {
        'id': id,
        'name': id,
        'colorValue': 0xFFE05446,
        'iconKey': 'work',
        'parentId': null,
        'isArchived': false,
      },
  ],
  'logs': <Object?>[],
  'plans': <Object?>[],
  'selectedCategoryId': ids.first,
  'plannedMinutes': 25,
  'themePreference': 'system',
  'accentColorValue': 0xFFE05446,
};

String _backupListing(Map<String, List<int>> files, int port) {
  final entries = files.entries.where(
    (entry) => entry.key.startsWith('/dav/tomatolog/backups/'),
  );
  return '''
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/tomatolog/backups/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
  ${entries.map((entry) => '<d:response><d:href>${entry.key}</d:href><d:propstat><d:prop><d:getcontentlength>${entry.value.length}</d:getcontentlength></d:prop></d:propstat></d:response>').join()}
</d:multistatus>
''';
}
