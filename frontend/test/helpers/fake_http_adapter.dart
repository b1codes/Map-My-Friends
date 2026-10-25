import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A canned reply for [FakeHttpAdapter].
class FakeResponse {
  final int statusCode;
  final Object? body;
  final Map<String, List<String>> headers;

  const FakeResponse(this.statusCode, [this.body, this.headers = const {}]);
}

/// Decides the reply to one request. Throw a [DioException] to simulate a
/// network failure (e.g. a timeout) instead of an HTTP status.
typedef FakeHandler = FutureOr<FakeResponse> Function(RequestOptions request);

/// An in-memory [HttpClientAdapter]: no sockets, every request answered by a
/// handler registered against `METHOD path`.
///
/// Paths are matched against the request URI's path with the base URL's path
/// stripped, so `'GET people/'` matches `http://localhost:8000/api/people/`.
/// An absolute URL such as an OSRM call is matched by its full path
/// (`'GET /route/v1/driving/...'`) or by [onAny].
///
/// Requests with no matching handler fail the test loudly with a 599 and a
/// message naming the route, rather than hanging.
class FakeHttpAdapter implements HttpClientAdapter {
  final Map<String, List<FakeHandler>> _routes = {};
  FakeHandler? _fallback;

  /// Every request the adapter received, in order.
  final List<RequestOptions> requests = [];

  /// Replies to `METHOD path`. Registering the same route again queues the
  /// handlers: each call consumes one, and the last one repeats.
  void on(String method, String path, FakeHandler handler) {
    _routes.putIfAbsent('${method.toUpperCase()} $path', () => []).add(handler);
  }

  /// Shorthand for a fixed reply.
  void reply(String method, String path, int status, [Object? body]) {
    on(method, path, (_) => FakeResponse(status, body));
  }

  /// Handles any request no route matched.
  void onAny(FakeHandler handler) => _fallback = handler;

  /// The requests sent to `METHOD path`.
  List<RequestOptions> requestsTo(String method, String path) => requests
      .where((r) => r.method == method.toUpperCase() && _pathOf(r) == path)
      .toList();

  static String _pathOf(RequestOptions request) {
    final uri = request.uri;
    final basePath = Uri.tryParse(request.baseUrl)?.path ?? '';
    final path = uri.path;
    if (basePath.isNotEmpty &&
        request.uri.host == Uri.tryParse(request.baseUrl)?.host &&
        path.startsWith(basePath)) {
      return path.substring(basePath.length);
    }
    return path;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final key = '${options.method} ${_pathOf(options)}';
    final queue = _routes[key];
    final FakeHandler? handler = queue == null || queue.isEmpty
        ? _fallback
        : (queue.length > 1 ? queue.removeAt(0) : queue.first);

    if (handler == null) {
      return ResponseBody.fromString(
        jsonEncode({'detail': 'FakeHttpAdapter: no handler for $key'}),
        599,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    final reply = await handler(options);
    final body = reply.body;
    return ResponseBody.fromString(
      body == null ? '' : (body is String ? body : jsonEncode(body)),
      reply.statusCode,
      headers: {
        if (body != null && body is! String)
          Headers.contentTypeHeader: [Headers.jsonContentType],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A Dio wired to [adapter], with the same base URL the app uses in tests.
Dio fakeDio(FakeHttpAdapter adapter, [BaseOptions? options]) =>
    Dio(options ?? BaseOptions(baseUrl: 'http://localhost:8000/api/'))
      ..httpClientAdapter = adapter;
