import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomatolog/services/webdav_service.dart';

void main() {
  late HttpServer server;
  late WebDavClient client;
  final requests = <String>[];
  final putConditions = <String?>[];

  setUp(() async {
    requests.clear();
    putConditions.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = WebDavClient(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}/dav/user/'),
      username: 'tomato',
      password: 'secret',
    );
    server.listen((request) async {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Basic dG9tYXRvOnNlY3JldA==',
      );
      requests.add('${request.method} ${request.uri.path}');
      if (request.method == 'PROPFIND' &&
          request.headers.value('Depth') == '1') {
        request.response.statusCode = 207;
        request.response.write('''
          <d:multistatus xmlns:d="DAV:">
            <d:response><d:href>/dav/user/tomatolog/backups/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
            <d:response><d:href>/dav/user/tomatolog/backups/backup%202026.json</d:href><d:propstat><d:prop><d:getlastmodified>Wed, 01 Jul 2026 08:00:00 GMT</d:getlastmodified><d:getcontentlength>42</d:getcontentlength></d:prop></d:propstat></d:response>
          </d:multistatus>
        ''');
      } else if (request.method == 'GET') {
        request.response.headers.set(HttpHeaders.etagHeader, '"remote-v2"');
        request.response.headers.set(
          HttpHeaders.lastModifiedHeader,
          'Wed, 01 Jul 2026 08:00:00 GMT',
        );
        request.response.write('{"ok":true}');
      } else if (request.method == 'MKCOL') {
        request.response.statusCode = HttpStatus.created;
      } else if (request.method == 'PUT') {
        putConditions.add(
          request.headers.value(HttpHeaders.ifMatchHeader) ??
              request.headers.value(HttpHeaders.ifNoneMatchHeader),
        );
        expect(await utf8.decoder.bind(request).join(), '{"ok":true}');
        request.response.statusCode =
            request.headers.value(HttpHeaders.ifMatchHeader) == '"stale"'
            ? HttpStatus.preconditionFailed
            : HttpStatus.created;
      } else if (request.method == 'DELETE') {
        request.response.statusCode = HttpStatus.noContent;
      } else {
        request.response.statusCode = 207;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('manages separate sync and backup directories and files', () async {
    await client.testConnection();
    await client.ensureAppDirectories();
    await client.put([
      ...client.syncPath,
      'current.json',
    ], utf8.encode('{"ok":true}'));
    expect(
      utf8.decode(await client.get([...client.syncPath, 'current.json'])),
      '{"ok":true}',
    );

    final files = await client.list(client.backupsPath);
    expect(files, hasLength(1));
    expect(files.single.name, 'backup 2026.json');
    expect(files.single.size, 42);
    expect(files.single.modifiedAt, DateTime(2026, 7, 1, 16));
    await client.delete([...client.backupsPath, files.single.name]);

    expect(
      requests,
      containsAll(<String>[
        'MKCOL /dav/user/tomatolog',
        'MKCOL /dav/user/tomatolog/sync',
        'MKCOL /dav/user/tomatolog/backups',
        'PUT /dav/user/tomatolog/sync/current.json',
        'DELETE /dav/user/tomatolog/backups/backup%202026.json',
      ]),
    );
  });

  test('rejects unsafe paths and invalid base URLs', () {
    expect(() => client.get(const ['..', 'secret']), throwsArgumentError);
    expect(
      () => WebDavClient(
        baseUrl: Uri.parse('ftp://example.com/files'),
        username: '',
        password: '',
      ),
      throwsArgumentError,
    );
  });

  test('reads validators and sends conditional PUT headers', () async {
    final path = [...client.syncPath, 'current.json'];
    final remote = await client.getFile(path);
    expect(utf8.decode(remote.bytes), '{"ok":true}');
    expect(remote.etag, '"remote-v2"');
    expect(remote.modifiedAt, DateTime(2026, 7, 1, 16));

    await client.put(path, utf8.encode('{"ok":true}'), ifMatch: remote.etag);
    await client.put(path, utf8.encode('{"ok":true}'), ifNoneMatch: '*');
    expect(putConditions, ['"remote-v2"', '*']);

    await expectLater(
      client.put(path, utf8.encode('{"ok":true}'), ifMatch: '"stale"'),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.preconditionFailed,
        ),
      ),
    );
  });
}
