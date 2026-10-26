import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_http_adapter.dart';
import '../services/service_test_support.dart';

/// The repo-root `contracts/` directory, shared with the Django provider
/// tests (backend/tests/contracts). Found by walking up from the working
/// directory, which `flutter test` sets to the package root.
final Directory contractsDir = () {
  var dir = Directory.current.absolute;
  while (true) {
    if (Directory('${dir.path}/contracts/api').existsSync()) {
      return Directory('${dir.path}/contracts');
    }
    if (dir.parent.path == dir.path) {
      throw StateError('No contracts/ above ${Directory.current.path}');
    }
    dir = dir.parent;
  }
}();

dynamic loadContractJson(String relativePath) =>
    jsonDecode(File('${contractsDir.path}/$relativePath').readAsStringSync());

/// contracts/api/fixtures.json: the shared world the interactions describe.
final Map<String, dynamic> contractFixtures =
    loadContractJson('api/fixtures.json') as Map<String, dynamic>;

/// The access token every `"auth": "user"` request is sent with.
const contractAccessToken = 'contract-access-token';

/// The refresh token the fixtures world hands out (its placeholder value).
final String contractRefreshToken =
    (contractFixtures['placeholders'] as Map<String, dynamic>).entries
        .firstWhere((entry) => entry.value == 'refresh_token')
        .key;

/// One HTTP interaction: a request the app sends and the response it gets.
class Interaction {
  final String id;
  final Map<String, dynamic> spec;

  Interaction(this.id, this.spec);

  Map<String, dynamic> get request => spec['request'] as Map<String, dynamic>;
  Map<String, dynamic> get response => spec['response'] as Map<String, dynamic>;

  String get method => request['method'] as String;
  String get path => request['path'] as String;
  int get status => response['status'] as int;
  dynamic get example => response['example'];

  /// The contract's response, served for [method] [path].
  FakeResponse get reply => FakeResponse(status, example);
}

/// Every app API interaction, keyed by id (the file name).
final Map<String, Interaction> apiInteractions = {
  for (final file in Directory(
    '${contractsDir.path}/api/interactions',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.json')))
    _stem(file): Interaction(
      _stem(file),
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    ),
};

/// A third-party interaction under `contracts/external/<provider>/`.
Interaction externalInteraction(String provider, String name) => Interaction(
  '$provider/$name',
  loadContractJson('external/$provider/$name.json') as Map<String, dynamic>,
);

String _stem(File file) {
  final name = file.uri.pathSegments.last;
  return name.substring(0, name.length - '.json'.length);
}

/// Round-trips a request body through JSON, as it goes over the wire.
dynamic _onTheWire(Object? data) => jsonDecode(jsonEncode(data));

/// Asserts [sent] is exactly the request [interaction] describes.
void expectRequestMatches(RequestOptions sent, Interaction interaction) {
  final request = interaction.request;
  final reason = interaction.id;

  expect(sent.method, request['method'], reason: reason);
  expect(
    sent.uri.path,
    Uri.parse(testBaseUrl).path + interaction.path,
    reason: reason,
  );
  expect(
    sent.uri.queryParameters,
    (request['query'] as Map<String, dynamic>?) ?? const {},
    reason: '$reason query',
  );

  switch (request['auth']) {
    case 'user':
      expect(
        authHeaderOf(sent),
        'Bearer $contractAccessToken',
        reason: '$reason auth',
      );
    case 'invalid':
      expect(authHeaderOf(sent), startsWith('Bearer '), reason: '$reason auth');
    default:
      expect(authHeaderOf(sent), isNull, reason: '$reason auth');
  }

  if (request.containsKey('json')) {
    expect(_onTheWire(sent.data), request['json'], reason: '$reason body');
  } else if (request.containsKey('multipart')) {
    final multipart = request['multipart'] as Map<String, dynamic>;
    expect(sent.data, isA<FormData>(), reason: '$reason body');
    final form = sent.data as FormData;
    expect(
      Map.fromEntries(form.fields),
      multipart['fields'],
      reason: '$reason form fields',
    );
    expect(
      {
        for (final file in form.files)
          file.key: {
            'filename': file.value.filename,
            'content_type': file.value.contentType.toString(),
          },
      },
      multipart['files'],
      reason: '$reason form files',
    );
  } else {
    expect(sent.data, isNull, reason: '$reason body');
  }
}
