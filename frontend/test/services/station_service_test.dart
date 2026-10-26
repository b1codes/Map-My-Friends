import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/services/station_service.dart';

import '../helpers/fake_http_adapter.dart';
import 'service_test_support.dart';

Map<String, dynamic> stationFeature(int id, String name) => {
  'type': 'Feature',
  'id': id,
  'geometry': {
    'type': 'Point',
    'coordinates': [-73.9935, 40.7506],
  },
  'properties': {
    'name': name,
    'osm_id': 1000 + id,
    'station_type': 'major_station',
    'uic_ref': '8000$id',
    'city': 'New York',
    'country': 'USA',
    'distance_km': 0.8,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHttpAdapter api;
  late StationService service;

  setUp(() {
    seedTokens(access: 'tok', refresh: 'ref');
    api = FakeHttpAdapter();
    service = StationService.forTesting(
      dio: fakeDio(api),
      authService: authServiceOn(FakeHttpAdapter()),
    );
  });

  test('the app-wide instance is a singleton', () {
    expect(StationService(), same(StationService()));
  });

  group('loadStationsFromAsset', () {
    test('parses the bundled stations file', () async {
      final stations = await service.loadStationsFromAsset();

      expect(stations.length, greaterThan(1000));
      expect(
        stations.every(
          (s) =>
              s.latitude.abs() <= 90 &&
              s.longitude.abs() <= 180 &&
              s.osmId > 0 &&
              s.name.isNotEmpty,
        ),
        isTrue,
      );
      expect(
        stations.map((s) => s.stationType).toSet(),
        containsAll(['major_station', 'regional_station']),
      );
      final first = stations.first;
      expect(first.name, '1');
      expect(first.osmId, 7966411005);
      expect(first.country, 'USA');
      expect(first.latitude, closeTo(25.798, 0.001));
    });
  });

  group('getNearestStations', () {
    test('sends lat, lon and the default count of 3 with the token', () async {
      api.reply('GET', 'stations/nearest/', 200, {
        'type': 'FeatureCollection',
        'features': [stationFeature(1, 'Penn'), stationFeature(2, 'Grand')],
      });

      final stations = await service.getNearestStations(40.75, -73.99);

      expect(stations.map((s) => s.name), ['Penn', 'Grand']);
      final penn = stations.first;
      expect(penn.id, 1);
      expect(penn.osmId, 1001);
      expect(penn.stationType, 'major_station');
      expect(penn.uicRef, '80001');
      expect(penn.latitude, 40.7506);
      expect(penn.longitude, -73.9935);
      expect(penn.distanceKm, 0.8);
      final request = api.requests.single;
      expect(request.method, 'GET');
      expect(request.queryParameters, {
        'lat': 40.75,
        'lon': -73.99,
        'count': 3,
      });
      expect(authHeaderOf(request), 'Bearer tok');
    });

    test('parses a bare list of features and passes a custom count', () async {
      api.reply('GET', 'stations/nearest/', 200, [stationFeature(7, 'Fulton')]);

      final stations = await service.getNearestStations(1, 2, count: 10);

      expect(stations.single.name, 'Fulton');
      expect(api.requests.single.queryParameters['count'], 10);
    });

    test('sends no Authorization header when signed out', () async {
      seedTokens();
      api.reply('GET', 'stations/nearest/', 200, <Object>[]);

      expect(await service.getNearestStations(1, 2), isEmpty);
      expect(api.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('rejects an unexpected response shape', () async {
      api.reply('GET', 'stations/nearest/', 200, {'stations': <Object>[]});

      await expectLater(
        service.getNearestStations(1, 2),
        throwsA(
          exceptionWith(
            'Failed to load nearest stations: '
            'Exception: Unexpected response format',
          ),
        ),
      );
    });

    test('rejects a non-200 success status', () async {
      api.reply('GET', 'stations/nearest/', 204);

      await expectLater(
        service.getNearestStations(1, 2),
        throwsA(
          exceptionWith(
            'Failed to load nearest stations: '
            'Exception: Failed to load nearest stations',
          ),
        ),
      );
    });

    test('wraps an HTTP error', () async {
      api.reply('GET', 'stations/nearest/', 500);

      await expectLater(
        service.getNearestStations(1, 2),
        throwsA(
          exceptionStartingWith(
            'Failed to load nearest stations: DioException',
          ),
        ),
      );
    });
  });
}
