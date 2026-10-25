import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/services/airport_service.dart';

import '../helpers/fake_http_adapter.dart';
import 'service_test_support.dart';

Map<String, dynamic> airportFeature(int id, String iata) => {
  'type': 'Feature',
  'id': id,
  'geometry': {
    'type': 'Point',
    'coordinates': [-73.7781, 40.6413],
  },
  'properties': {
    'name': '$iata Airport',
    'iata_code': iata,
    'icao_code': 'K$iata',
    'airport_type': 'large_airport',
    'city': 'New York',
    'country': 'US',
    'continent': 'NA',
    'distance_km': 12.3,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHttpAdapter api;
  late FakeHttpAdapter authBackend;
  late AirportService service;

  setUp(() {
    seedTokens(access: 'tok', refresh: 'ref');
    api = FakeHttpAdapter();
    authBackend = FakeHttpAdapter();
    service = AirportService.forTesting(
      dio: fakeDio(api),
      authService: authServiceOn(authBackend),
    );
  });

  test('the app-wide instance is a singleton', () {
    expect(AirportService(), same(AirportService()));
  });

  group('loadAirportsFromAsset', () {
    test('parses the bundled airports file', () async {
      final airports = await service.loadAirportsFromAsset();

      expect(airports.length, greaterThan(1000));
      expect(airports.every((a) => a.iataCode.length == 3), isTrue);
      expect(
        airports.every(
          (a) =>
              a.latitude.abs() <= 90 &&
              a.longitude.abs() <= 180 &&
              a.name.isNotEmpty,
        ),
        isTrue,
      );
      final jfk = airports.singleWhere((a) => a.iataCode == 'JFK');
      expect(jfk.city, 'New York');
      expect(jfk.country, 'US');
      expect(jfk.airportType, 'large_airport');
      expect(jfk.latitude, closeTo(40.64, 0.01));
      expect(jfk.longitude, closeTo(-73.78, 0.01));
    });
  });

  group('getNearestAirports', () {
    test('sends lat, lon and the default count of 3 with the token', () async {
      api.reply('GET', 'airports/nearest/', 200, {
        'type': 'FeatureCollection',
        'features': [airportFeature(1, 'JFK'), airportFeature(2, 'LGA')],
      });

      final airports = await service.getNearestAirports(40.7, -74.0);

      expect(airports.map((a) => a.iataCode), ['JFK', 'LGA']);
      final jfk = airports.first;
      expect(jfk.id, 1);
      expect(jfk.icaoCode, 'KJFK');
      expect(jfk.continent, 'NA');
      expect(jfk.latitude, 40.6413);
      expect(jfk.longitude, -73.7781);
      expect(jfk.distanceKm, 12.3);
      final request = api.requests.single;
      expect(request.method, 'GET');
      expect(request.queryParameters, {'lat': 40.7, 'lon': -74.0, 'count': 3});
      expect(authHeaderOf(request), 'Bearer tok');
    });

    test('parses a bare list of features and passes a custom count', () async {
      api.reply('GET', 'airports/nearest/', 200, [airportFeature(5, 'EWR')]);

      final airports = await service.getNearestAirports(1, 2, count: 1);

      expect(airports.single.iataCode, 'EWR');
      expect(api.requests.single.queryParameters['count'], 1);
    });

    test('sends no Authorization header when signed out', () async {
      seedTokens();
      api.reply('GET', 'airports/nearest/', 200, <Object>[]);

      expect(await service.getNearestAirports(1, 2), isEmpty);
      expect(api.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('rejects an unexpected response shape', () async {
      api.reply('GET', 'airports/nearest/', 200, {'airports': <Object>[]});

      await expectLater(
        service.getNearestAirports(1, 2),
        throwsA(
          exceptionWith(
            'Failed to load nearest airports: '
            'Exception: Unexpected response format',
          ),
        ),
      );
    });

    test('rejects a non-200 success status', () async {
      api.reply('GET', 'airports/nearest/', 204);

      await expectLater(
        service.getNearestAirports(1, 2),
        throwsA(
          exceptionWith(
            'Failed to load nearest airports: '
            'Exception: Failed to load nearest airports',
          ),
        ),
      );
    });

    test('wraps an HTTP error', () async {
      api.reply('GET', 'airports/nearest/', 500);

      await expectLater(
        service.getNearestAirports(1, 2),
        throwsA(
          exceptionStartingWith(
            'Failed to load nearest airports: DioException',
          ),
        ),
      );
      expect(authBackend.requests, isEmpty);
    });

    test(
      'on a 401, refreshes the token and retries with the new one',
      () async {
        final sentHeaders = <String?>[];
        api.on('GET', 'airports/nearest/', (r) {
          sentHeaders.add(authHeaderOf(r));
          return const FakeResponse(401);
        });
        api.on('GET', 'airports/nearest/', (r) {
          sentHeaders.add(authHeaderOf(r));
          return FakeResponse(200, {
            'type': 'FeatureCollection',
            'features': [airportFeature(1, 'JFK')],
          });
        });
        authBackend.reply('POST', 'user/auth/token/refresh/', 200, {
          'access': 'fresh',
        });

        final airports = await service.getNearestAirports(1, 2);

        expect(airports.single.iataCode, 'JFK');
        expect(sentHeaders, ['Bearer tok', 'Bearer fresh']);
        expect(
          authBackend
              .requestsTo('POST', 'user/auth/token/refresh/')
              .single
              .data,
          {'refresh': 'ref'},
        );
      },
    );

    test('propagates the 401 when the refresh fails', () async {
      api.reply('GET', 'airports/nearest/', 401);
      authBackend.reply('POST', 'user/auth/token/refresh/', 401);

      await expectLater(
        service.getNearestAirports(1, 2),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(
              startsWith('Exception: Failed to load nearest airports: '),
              contains('401'),
            ),
          ),
        ),
      );
      expect(api.requests, hasLength(1));
      expect(await storedValues(), isEmpty);
    });
  });
}
