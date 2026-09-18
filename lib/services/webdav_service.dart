import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal WebDAV client for the app's synchronization and backup files.
class WebDavClient {
  WebDavClient({
    required Uri baseUrl,
    required String username,
    required String password,
    this.timeout = const Duration(seconds: 15),
    HttpClient? httpClient,
  }) : baseUrl = _validateBaseUrl(baseUrl),
       _authorization =
           'Basic ${base64Encode(utf8.encode('$username:$password'))}',
       _httpClient = httpClient ?? HttpClient();

  static const appDirectory = 'tomatolog';
  static const syncDirectory = 'sync';
  static const backupsDirectory = 'backups';

  final Uri baseUrl;
  final Duration timeout;
  final String _authorization;
  final HttpClient _httpClient;

  List<String> get syncPath => const [appDirectory, syncDirectory];
  List<String> get backupsPath => const [appDirectory, backupsDirectory];

  Future<void> testConnection() async {
    final response = await _request(
      'PROPFIND',
      const [],
      headers: const {'Depth': '0'},
    );
    await _expect(response, const {HttpStatus.ok, 207});
  }

  Future<void> ensureAppDirectories() async {
    await ensureCollection(const [appDirectory]);
    await ensureCollection(syncPath);
    await ensureCollection(backupsPath);
  }

  Future<void> ensureCollection(List<String> path) async {
    final response = await _request('MKCOL', path);
    await _expect(response, const {
      HttpStatus.ok,
      HttpStatus.created,
      HttpStatus.noContent,
      HttpStatus.methodNotAllowed,
    });
  }

  Future<List<WebDavEntry>> list(List<String> path) async {
    final response = await _request(
      'PROPFIND',
      path,
      headers: const {'Depth': '1'},
    );
    final body = await _expect(response, const {207, HttpStatus.ok});
    return _parseEntries(utf8.decode(body, allowMalformed: true), _uri(path));
  }

  Future<List<int>> get(List<String> path) async {
    return (await getFile(path)).bytes;
  }

  Future<WebDavFile> getFile(List<String> path) async {
    final response = await _request('GET', path);
    final etag = response.headers.value(HttpHeaders.etagHeader);
    final modified = response.headers.value(HttpHeaders.lastModifiedHeader);
    final bytes = await _expect(response, const {HttpStatus.ok});
    return WebDavFile(
      bytes: bytes,
      etag: etag,
      modifiedAt: modified == null ? null : _parseHttpDate(modified),
    );
  }

  Future<void> put(
    List<String> path,
    List<int> bytes, {
    String contentType = 'application/json; charset=utf-8',
    String? ifMatch,
    String? ifNoneMatch,
  }) async {
    final headers = <String, String>{'Content-Type': contentType};
    if (ifMatch != null) headers[HttpHeaders.ifMatchHeader] = ifMatch;
    if (ifNoneMatch != null) {
      headers[HttpHeaders.ifNoneMatchHeader] = ifNoneMatch;
    }
    final response = await _request('PUT', path, headers: headers, body: bytes);
    await _expect(response, const {
      HttpStatus.ok,
      HttpStatus.created,
      HttpStatus.noContent,
    });
  }

  Future<void> delete(List<String> path) async {
    final response = await _request('DELETE', path);
    await _expect(response, const {
      HttpStatus.ok,
      HttpStatus.accepted,
      HttpStatus.noContent,
      HttpStatus.notFound,
    });
  }

  void close() => _httpClient.close(force: true);

  Future<HttpClientResponse> _request(
    String method,
    List<String> path, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    try {
      final request = await _httpClient
          .openUrl(method, _uri(path))
          .timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, _authorization);
      request.headers.set(HttpHeaders.userAgentHeader, 'tomatolog/0.0.5');
      headers.forEach(request.headers.set);
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }
      return await request.close().timeout(timeout);
    } on TimeoutException catch (error) {
      throw WebDavException('连接 WebDAV 超时', cause: error);
    } on SocketException catch (error) {
      throw WebDavException('无法连接 WebDAV：${error.message}', cause: error);
    } on HandshakeException catch (error) {
      throw WebDavException('WebDAV TLS 连接失败', cause: error);
    }
  }

  Future<List<int>> _expect(
    HttpClientResponse response,
    Set<int> expected,
  ) async {
    late final List<int> bytes;
    try {
      bytes = await response
          .fold<List<int>>(<int>[], (all, chunk) {
            all.addAll(chunk);
            return all;
          })
          .timeout(timeout);
    } on TimeoutException catch (error) {
      throw WebDavException('读取 WebDAV 响应超时', cause: error);
    }
    if (!expected.contains(response.statusCode)) {
      final detail = utf8
          .decode(bytes.take(512).toList(), allowMalformed: true)
          .trim();
      throw WebDavException(
        'WebDAV 请求失败（${response.statusCode} ${response.reasonPhrase}）'
        '${detail.isEmpty ? '' : '：$detail'}',
        statusCode: response.statusCode,
      );
    }
    return bytes;
  }

  Uri _uri(List<String> path) {
    for (final segment in path) {
      if (segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.contains('/') ||
          segment.contains(r'\') ||
          segment.contains('\u0000')) {
        throw ArgumentError.value(segment, 'path', 'WebDAV 路径段无效');
      }
    }
    final relative = Uri(pathSegments: path).toString();
    return baseUrl.resolve(relative);
  }

  static Uri _validateBaseUrl(Uri value) {
    if ((value.scheme != 'http' && value.scheme != 'https') ||
        value.host.isEmpty ||
        value.hasQuery ||
        value.hasFragment ||
        value.userInfo.isNotEmpty) {
      throw ArgumentError.value(value, 'baseUrl', '必须是无查询参数和账号信息的 HTTP(S) 地址');
    }
    final path = value.path.endsWith('/') ? value.path : '${value.path}/';
    return value.replace(path: path);
  }

  static List<WebDavEntry> _parseEntries(String xml, Uri collectionUri) {
    final entries = <WebDavEntry>[];
    final responsePattern = RegExp(
      r'<(?:[\w.-]+:)?response\b[^>]*>([\s\S]*?)</(?:[\w.-]+:)?response\s*>',
      caseSensitive: false,
    );
    for (final response in responsePattern.allMatches(xml)) {
      final block = response.group(1)!;
      final href = _tagValue(block, 'href');
      if (href == null) continue;
      final decodedHref = _decodeXml(href.trim());
      final uri = collectionUri.resolve(decodedHref);
      if (_sameCollection(uri, collectionUri)) continue;
      final pathSegments = uri.pathSegments
          .where((part) => part.isNotEmpty)
          .toList();
      if (pathSegments.isEmpty) continue;
      final modified = _tagValue(block, 'getlastmodified');
      final size = _tagValue(block, 'getcontentlength');
      entries.add(
        WebDavEntry(
          uri: uri,
          name: pathSegments.last,
          isCollection: RegExp(
            r'<(?:[\w.-]+:)?collection(?:\s[^>]*)?\s*/?>',
            caseSensitive: false,
          ).hasMatch(block),
          modifiedAt: modified == null ? null : _parseHttpDate(modified.trim()),
          size: size == null ? null : int.tryParse(size.trim()),
        ),
      );
    }
    return entries;
  }

  static String? _tagValue(String xml, String tag) => RegExp(
    '<(?:[\\w.-]+:)?$tag\\b[^>]*>([\\s\\S]*?)</(?:[\\w.-]+:)?$tag\\s*>',
    caseSensitive: false,
  ).firstMatch(xml)?.group(1);

  static DateTime? _parseHttpDate(String value) {
    try {
      return HttpDate.parse(value).toLocal();
    } on FormatException {
      return DateTime.tryParse(value)?.toLocal();
    }
  }

  static String _decodeXml(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  static bool _sameCollection(Uri left, Uri right) =>
      left
          .replace(query: '', fragment: '')
          .path
          .replaceAll(RegExp(r'/+$'), '') ==
      right
          .replace(query: '', fragment: '')
          .path
          .replaceAll(RegExp(r'/+$'), '');
}

class WebDavEntry {
  const WebDavEntry({
    required this.uri,
    required this.name,
    required this.isCollection,
    this.modifiedAt,
    this.size,
  });

  final Uri uri;
  final String name;
  final bool isCollection;
  final DateTime? modifiedAt;
  final int? size;
}

class WebDavFile {
  const WebDavFile({required this.bytes, this.etag, this.modifiedAt});

  final List<int> bytes;
  final String? etag;
  final DateTime? modifiedAt;
}

class WebDavException implements Exception {
  const WebDavException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => message;
}
