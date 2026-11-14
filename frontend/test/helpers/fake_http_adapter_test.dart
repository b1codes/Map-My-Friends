import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late Dio dio;

  setUp(() {
    adapter = FakeHttpAdapter();
    dio = fakeDio(adapter);
  });

  test('matches routes relative to the base URL and decodes JSON', () async {
    adapter.reply('GET', 'people/', 200, [
      {'id': '1'},
    ]);

    final response = await dio.get<dynamic>('people/');

    expect(response.statusCode, 200);
    expect(response.data, [
      {'id': '1'},
    ]);
    expect(adapter.requestsTo('GET', 'people/'), hasLength(1));
  });

  test('matches absolute URLs by their full path', () async {
    adapter.reply('GET', '/route/v1/driving/1,2;3,4', 200, {
      'routes': <dynamic>[],
    });

    final response = await dio.get<dynamic>(
      'https://router.example.org/route/v1/driving/1,2;3,4',
    );

    expect(response.data, {'routes': <dynamic>[]});
  });

  test('queued handlers are consumed in order and the last repeats', () async {
    adapter.reply('GET', 'x/', 401);
    adapter.reply('GET', 'x/', 200, 'ok');
    final codes = <int>[];
    for (var i = 0; i < 3; i++) {
      final r = await dio.get<dynamic>(
        'x/',
        options: Options(validateStatus: (_) => true),
      );
      codes.add(r.statusCode!);
    }
    expect(codes, [401, 200, 200]);
  });

  test('an unrouted request fails loudly with a 599', () async {
    await expectLater(
      dio.get<dynamic>('nope/'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          599,
        ),
      ),
    );
  });
}
