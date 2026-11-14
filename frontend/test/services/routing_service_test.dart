import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/services/routing_service.dart';

import '../helpers/fake_http_adapter.dart';
import 'service_test_support.dart';

/// The OSRM path for a segment, in OSRM's lon,lat order.
String osrmPath(LatLng a, LatLng b) =>
    '/route/v1/driving/${a.longitude},${a.latitude};${b.longitude},${b.latitude}';

/// An OSRM reply whose single route follows [points] (given as LatLng and
/// encoded as GeoJSON [lon, lat] pairs).
Map<String, dynamic> osrmRoute(List<LatLng> points) => {
  'code': 'Ok',
  'routes': [
    {
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          for (final p in points) [p.longitude, p.latitude],
        ],
      },
    },
  ],
};

void main() {
  late RoutingService routingService;
  late FakeHttpAdapter adapter;

  setUp(() {
    adapter = FakeHttpAdapter();
    routingService = RoutingService(dio: fakeDio(adapter));
  });

  group('RoutingService', () {
    final personA = Person(
      id: '1',
      firstName: 'A',
      lastName: 'User',
      relationshipTag: 'Friend',
      city: 'City',
      state: 'State',
      country: 'Country',
      latitude: 10.0,
      longitude: 10.0,
    );

    final airport = Airport(
      name: 'Hub',
      iataCode: 'HUB',
      airportType: 'large_airport',
      city: 'City',
      country: 'XX',
      latitude: 30.0,
      longitude: 30.0,
    );

    final station = Station(
      name: 'Central',
      osmId: 1,
      latitude: 40.0,
      longitude: 40.0,
    );

    const locA = LatLng(10.0, 10.0);
    const locB = LatLng(20.0, 25.0);
    const locC = LatLng(30.0, 35.0);

    final stopA = TripStop(
      id: 's1',
      people: [personA],
      location: locA,
      sequenceOrder: 0,
    );
    final stopB = TripStop(
      id: 's2',
      people: [personA],
      location: locB,
      sequenceOrder: 1,
    );
    final stopC = TripStop(
      id: 's3',
      people: [personA],
      location: locC,
      sequenceOrder: 2,
    );

    test('getRoute returns straight line for non-person stops', () async {
      final stopStation = TripStop(
        id: 's3',
        location: const LatLng(12.0, 12.0),
        sequenceOrder: 2,
      );

      final route = await routingService.getRoute([stopA, stopStation]);

      expect(route.length, 2);
      expect(route[0], const LatLng(10.0, 10.0));
      expect(route[1], const LatLng(12.0, 12.0));
      expect(adapter.requests, isEmpty);
    });

    test('never sends the signed-in user\'s token to OSRM', () async {
      // OSRM is a public third-party host. Regression: the default instance
      // used ApiService's Dio, whose interceptor attaches the app JWT.
      seedTokens(access: 'user-jwt', refresh: 'r');
      final service = RoutingService();
      service.dio.httpClientAdapter = adapter;
      adapter.onAny((_) => FakeResponse(200, osrmRoute([locA, locB])));

      await service.getRoute([stopA, stopB]);

      final osrm = adapter.requests.single;
      expect(osrm.uri.host, 'router.project-osrm.org');
      expect(authHeaderOf(osrm), isNull);
    });

    test('works with its default client', () async {
      // No network: fewer than two stops never reaches the HTTP client.
      expect(await RoutingService().getRoute([stopA]), isEmpty);
    });

    test('getRoute returns empty for less than 2 stops', () async {
      expect(await routingService.getRoute([stopA]), isEmpty);
      expect(await routingService.getRoute([]), isEmpty);
      expect(adapter.requests, isEmpty);
    });

    group('person to person segments', () {
      test('request an OSRM driving route in lon,lat order', () async {
        adapter.reply(
          'GET',
          osrmPath(locA, locB),
          200,
          osrmRoute([locA, locB]),
        );

        await routingService.getRoute([stopA, stopB]);

        final uri = adapter.requests.single.uri;
        expect(uri.host, 'router.project-osrm.org');
        expect(uri.path, '/route/v1/driving/10.0,10.0;25.0,20.0');
        expect(uri.queryParameters, {
          'overview': 'full',
          'geometries': 'geojson',
        });
      });

      test('convert the GeoJSON coordinates to LatLng', () async {
        const mid = LatLng(15.5, 17.25);
        adapter.reply(
          'GET',
          osrmPath(locA, locB),
          200,
          // Integer coordinates must also be accepted.
          {
            'routes': [
              {
                'geometry': {
                  'coordinates': [
                    [10, 10],
                    [mid.longitude, mid.latitude],
                    [25, 20],
                  ],
                },
              },
            ],
          },
        );

        final route = await routingService.getRoute([stopA, stopB]);

        expect(route, [locA, mid, locB]);
      });

      test('drop the duplicated join point between OSRM segments', () async {
        const ab = LatLng(15.0, 18.0);
        const bc = LatLng(25.0, 30.0);
        adapter.reply(
          'GET',
          osrmPath(locA, locB),
          200,
          osrmRoute([locA, ab, locB]),
        );
        adapter.reply(
          'GET',
          osrmPath(locB, locC),
          200,
          osrmRoute([locB, bc, locC]),
        );

        final route = await routingService.getRoute([stopA, stopB, stopC]);

        expect(route, [locA, ab, locB, bc, locC]);
        expect(adapter.requests, hasLength(2));
      });

      test('fall back to a straight line on an OSRM error status', () async {
        adapter.reply('GET', osrmPath(locA, locB), 500, {'code': 'Error'});

        expect(await routingService.getRoute([stopA, stopB]), [locA, locB]);
      });

      test('fall back to a straight line on a network failure', () async {
        adapter.on(
          'GET',
          osrmPath(locA, locB),
          (r) => throw DioException.connectionTimeout(
            timeout: const Duration(seconds: 5),
            requestOptions: r,
          ),
        );

        expect(await routingService.getRoute([stopA, stopB]), [locA, locB]);
      });

      test('fall back to a straight line when OSRM finds no route', () async {
        adapter.reply('GET', osrmPath(locA, locB), 200, {
          'code': 'NoRoute',
          'routes': <Object>[],
        });

        expect(await routingService.getRoute([stopA, stopB]), [locA, locB]);
      });

      test('fall back to a straight line when routes are missing', () async {
        adapter.reply('GET', osrmPath(locA, locB), 200, {'code': 'Ok'});

        expect(await routingService.getRoute([stopA, stopB]), [locA, locB]);
      });

      test('fall back to a straight line on a non-200 success', () async {
        adapter.reply(
          'GET',
          osrmPath(locA, locB),
          203,
          osrmRoute([locA, const LatLng(1, 1), locB]),
        );

        expect(await routingService.getRoute([stopA, stopB]), [locA, locB]);
      });

      test('fall back to a straight line on a malformed body', () async {
        adapter.reply('GET', osrmPath(locA, locB), 200, 'not json');

        expect(await routingService.getRoute([stopA, stopB]), [locA, locB]);
      });

      test('mix routed and fallback segments without duplicates', () async {
        const ab = LatLng(15.0, 18.0);
        adapter.reply(
          'GET',
          osrmPath(locA, locB),
          200,
          osrmRoute([locA, ab, locB]),
        );
        adapter.reply('GET', osrmPath(locB, locC), 500);

        final route = await routingService.getRoute([stopA, stopB, stopC]);

        expect(route, [locA, ab, locB, locC]);
      });

      test('start with a fallback segment, then append a routed one', () async {
        const bc = LatLng(25.0, 30.0);
        adapter.reply('GET', osrmPath(locA, locB), 500);
        adapter.reply(
          'GET',
          osrmPath(locB, locC),
          200,
          osrmRoute([locB, bc, locC]),
        );

        final route = await routingService.getRoute([stopA, stopB, stopC]);

        expect(route, [locA, locB, bc, locC]);
      });
    });

    group('airport and station segments', () {
      final airportStop = TripStop(
        id: 'air',
        people: [personA],
        airport: airport,
        location: const LatLng(30.0, 30.0),
        sequenceOrder: 1,
      );
      final stationStop = TripStop(
        id: 'rail',
        station: station,
        location: const LatLng(40.0, 40.0),
        sequenceOrder: 2,
      );

      test('are straight lines, even when the stop also has people', () async {
        final route = await routingService.getRoute([
          stopA,
          airportStop,
          stationStop,
        ]);

        expect(route, [
          locA,
          const LatLng(30.0, 30.0),
          const LatLng(40.0, 40.0),
        ]);
        expect(adapter.requests, isEmpty);
      });

      test(
        'only the person-only segments are routed in a mixed trip',
        () async {
          const ab = LatLng(15.0, 18.0);
          final finalStop = TripStop(
            id: 'end',
            people: [personA],
            location: locC,
            sequenceOrder: 3,
          );
          adapter.reply(
            'GET',
            osrmPath(locA, locB),
            200,
            osrmRoute([locA, ab, locB]),
          );
          // station -> person is a straight line: no OSRM call for it.

          final route = await routingService.getRoute([
            stopA,
            stopB,
            stationStop,
            finalStop,
          ]);

          expect(route, [locA, ab, locB, const LatLng(40.0, 40.0), locC]);
          expect(adapter.requests.map((r) => r.uri.path), [
            osrmPath(locA, locB),
          ]);
        },
      );
    });
  });
}
