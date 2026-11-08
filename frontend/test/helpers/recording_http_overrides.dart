import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One request as it left the app: method, full URL, headers and body, read
/// off the `dart:io` [HttpClient] after every Dio interceptor and every
/// `package:http` client wrapper has run.
class RecordedRequest {
  final String method;
  final Uri uri;

  /// Header names lower-cased, as `dart:io` does.
  final Map<String, List<String>> headers;
  final List<int> body;

  RecordedRequest(this.method, this.uri, this.headers, this.body);

  String get bodyText => utf8.decode(body, allowMalformed: true);

  @override
  String toString() => '$method $uri';
}

/// The reply [RecordingHttpOverrides] gives one request.
class CannedResponse {
  final int statusCode;
  final List<int> body;
  final Map<String, List<String>> headers;

  const CannedResponse(this.statusCode, this.body, [this.headers = const {}]);

  CannedResponse.json(this.statusCode, Object? json)
    : body = utf8.encode(jsonEncode(json)),
      headers = const {
        'content-type': ['application/json; charset=utf-8'],
      };
}

typedef Responder = CannedResponse Function(RecordedRequest request);

/// [HttpOverrides] whose every [HttpClient] answers in memory and records
/// what it was asked for.
///
/// This sits below everything the app controls: Dio's default
/// `IOHttpClientAdapter`, `package:http`'s `IOClient` (flutter_map's
/// `NetworkTileProvider`) and Flutter's `NetworkImage` all create their
/// client through `HttpClient()`, which consults [HttpOverrides.current]. So a
/// service built exactly as the app builds it, interceptors and all, is
/// observed without injecting anything into it.
class RecordingHttpOverrides extends HttpOverrides {
  final List<RecordedRequest> requests = [];

  /// Answers each request; replace it per test. Defaults to an empty 404.
  Responder responder = (_) => const CannedResponse(404, []);

  /// Time every reply takes to arrive, for a slow network. It runs on the
  /// test's clock, so a `tester.pump(latency)` delivers it.
  Duration latency = Duration.zero;

  /// When true, every request fails with a [SocketException] as it would
  /// with no connection. The request is still recorded.
  bool offline = false;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RecordingHttpClient(this);
}

class _RecordingHttpClient implements HttpClient {
  final RecordingHttpOverrides _owner;

  _RecordingHttpClient(this._owner);

  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _RecordingRequest(_owner, method.toUpperCase(), url);

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => openUrl(method, Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'RecordingHttpOverrides: HttpClient.${invocation.memberName} is not faked',
  );
}

class _RecordingRequest implements HttpClientRequest {
  final RecordingHttpOverrides _owner;
  @override
  final String method;
  @override
  final Uri uri;
  @override
  final HttpHeaders headers = _FakeHeaders();
  final List<int> _body = [];
  final Completer<HttpClientResponse> _done = Completer();

  _RecordingRequest(this._owner, this.method, this.uri);

  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;
  @override
  int contentLength = -1;
  @override
  bool bufferOutput = true;
  @override
  Encoding encoding = utf8;

  @override
  List<Cookie> get cookies => [];

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  void add(List<int> data) => _body.addAll(data);

  @override
  void write(Object? object) => _body.addAll(encoding.encode('$object'));

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> flush() async {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> get done => _done.future;

  @override
  Future<HttpClientResponse> close() {
    if (!_done.isCompleted) {
      final recorded = RecordedRequest(method, uri, {
        for (final e in (headers as _FakeHeaders)._values.entries)
          e.key: List.unmodifiable(e.value),
      }, List.unmodifiable(_body));
      _owner.requests.add(recorded);
      final Future<HttpClientResponse> reply;
      if (_owner.offline) {
        reply = Future.delayed(
          _owner.latency,
          () => throw SocketException(
            'Offline (RecordingHttpOverrides)',
            osError: const OSError('Network is unreachable', 101),
          ),
        );
      } else if (_owner.latency > Duration.zero) {
        reply = Future.delayed(
          _owner.latency,
          () => _FakeResponse(_owner.responder(recorded)),
        );
      } else {
        reply = Future.value(_FakeResponse(_owner.responder(recorded)));
      }
      _done.complete(reply);
    }
    return _done.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'RecordingHttpOverrides: HttpClientRequest.${invocation.memberName} '
    'is not faked',
  );
}

class _FakeHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [_stringify(value)];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => []).add(_stringify(value));
  }

  static String _stringify(Object value) =>
      value is Iterable ? value.join(', ') : value.toString();

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  String? value(String name) => _values[name.toLowerCase()]?.join(', ');

  @override
  void remove(String name, Object value) =>
      _values[name.toLowerCase()]?.remove(value.toString());

  @override
  void removeAll(String name) => _values.remove(name.toLowerCase());

  @override
  void clear() => _values.clear();

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach(action);

  @override
  int contentLength = -1;
  @override
  bool chunkedTransferEncoding = false;
  @override
  bool persistentConnection = true;
  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'RecordingHttpOverrides: HttpHeaders.${invocation.memberName} is not faked',
  );
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  final CannedResponse _reply;
  final _FakeHeaders _headers = _FakeHeaders();

  _FakeResponse(this._reply) {
    _reply.headers.forEach((k, vs) {
      for (final v in vs) {
        _headers.add(k, v);
      }
    });
  }

  @override
  int get statusCode => _reply.statusCode;
  @override
  String get reasonPhrase => _reply.statusCode < 400 ? 'OK' : 'Error';
  @override
  int get contentLength => _reply.body.length;
  @override
  HttpHeaders get headers => _headers;
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  bool get persistentConnection => true;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  X509Certificate? get certificate => null;
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  List<Cookie> get cookies => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([_reply.body]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'RecordingHttpOverrides: HttpClientResponse.${invocation.memberName} '
    'is not faked',
  );
}
