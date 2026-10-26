import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/services/routing_service.dart';
import 'package:map_my_friends/services/api_service.dart';

class MockRoutingService extends Mock implements RoutingService {}

class MockApiService extends Mock implements ApiService {}

Person _person(
  String id, {
  double? lat = 10.0,
  double? lng = 10.0,
  Airport? airport,
  Station? station,
}) => Person(
  id: id,
  firstName: 'Test$id',
  lastName: 'User',
  relationshipTag: 'Friend',
  city: 'City',
  state: 'State',
  country: 'Country',
  latitude: lat,
  longitude: lng,
  preferredAirport: airport,
  preferredStation: station,
);

TripStop _stop(int order, {double lat = 0, double lng = 0, String? id}) =>
    TripStop(id: id, location: LatLng(lat, lng), sequenceOrder: order);

List<double> _lngs(List<TripStop> stops) =>
    stops.map((s) => s.location.longitude).toList();

List<int> _orders(List<TripStop> stops) =>
    stops.map((s) => s.sequenceOrder).toList();

void main() {
  late MockRoutingService routingService;
  late MockApiService apiService;
  late TripBloc tripBloc;

  final testPerson = _person('1');

  final ord = Airport(
    id: 7,
    name: "O'Hare",
    iataCode: 'ORD',
    airportType: 'large_airport',
    city: 'Chicago',
    country: 'US',
    latitude: 41.97,
    longitude: -87.90,
  );
  final union = Station(
    id: 9,
    name: 'Union Station',
    osmId: 1,
    latitude: 41.87,
    longitude: -87.64,
  );

  const route = [LatLng(0, 0), LatLng(1, 1)];

  setUpAll(() {
    registerFallbackValue(const TripState());
    registerFallbackValue(testPerson);
    registerFallbackValue(<TripStop>[]);
    registerFallbackValue(
      Trip(name: 'Test Trip', date: DateTime(2026), stops: const []),
    );
  });

  setUp(() {
    routingService = MockRoutingService();
    apiService = MockApiService();
    tripBloc = TripBloc(routingService: routingService, apiService: apiService);

    when(() => routingService.getRoute(any())).thenAnswer((_) async => route);
  });

  tearDown(() {
    tripBloc.close();
  });

  List<TripStop> routedStops() =>
      verify(() => routingService.getRoute(captureAny())).captured.last
          as List<TripStop>;

  test('initial state is empty TripState', () {
    expect(tripBloc.state, const TripState());
  });

  group('AddStop', () {
    blocTest<TripBloc, TripState>(
      'adds the person at their home, then applies the route',
      build: () => tripBloc,
      act: (bloc) => bloc.add(AddStop(testPerson)),
      expect: () => [
        isA<TripState>()
            .having((s) => s.stops.single.people, 'people', [testPerson])
            .having(
              (s) => s.stops.single.location,
              'location',
              const LatLng(10, 10),
            )
            .having((s) => s.stops.single.sequenceOrder, 'order', 0)
            .having((s) => s.isOptimizing, 'isOptimizing', true)
            .having((s) => s.routePoints, 'routePoints', isEmpty),
        isA<TripState>()
            .having((s) => s.isOptimizing, 'isOptimizing', false)
            .having((s) => s.routePoints, 'routePoints', route),
      ],
      verify: (_) {
        expect(routedStops(), hasLength(1));
      },
    );

    blocTest<TripBloc, TripState>(
      'ignores a person with no coordinates',
      build: () => tripBloc,
      act: (bloc) => bloc
        ..add(AddStop(_person('2', lat: null)))
        ..add(AddStop(_person('3', lng: null))),
      expect: () => <TripState>[],
      verify: (_) => verifyNever(() => routingService.getRoute(any())),
    );

    blocTest<TripBloc, TripState>(
      "snaps the stop to the person's preferred airport",
      build: () => tripBloc,
      act: (bloc) => bloc.add(AddStop(_person('2', airport: ord))),
      skip: 1,
      expect: () => [
        isA<TripState>()
            .having((s) => s.stops.single.airport, 'airport', same(ord))
            .having((s) => s.stops.single.station, 'station', isNull)
            .having(
              (s) => s.stops.single.location,
              'location',
              LatLng(ord.latitude, ord.longitude),
            ),
      ],
    );

    blocTest<TripBloc, TripState>(
      'prefers the airport over the station when both are set',
      build: () => tripBloc,
      act: (bloc) =>
          bloc.add(AddStop(_person('2', airport: ord, station: union))),
      skip: 1,
      expect: () => [
        isA<TripState>().having(
          (s) => s.stops.single.location,
          'location',
          LatLng(ord.latitude, ord.longitude),
        ),
      ],
    );

    blocTest<TripBloc, TripState>(
      "falls back to the person's preferred station",
      build: () => tripBloc,
      act: (bloc) => bloc.add(AddStop(_person('2', station: union))),
      skip: 1,
      expect: () => [
        isA<TripState>()
            .having((s) => s.stops.single.station, 'station', same(union))
            .having(
              (s) => s.stops.single.location,
              'location',
              LatLng(union.latitude, union.longitude),
            ),
      ],
    );

    blocTest<TripBloc, TripState>(
      'appends after existing stops with the next sequence number',
      build: () => tripBloc,
      seed: () => TripState(stops: [_stop(0), _stop(1, lng: 5)]),
      act: (bloc) => bloc.add(AddStop(testPerson)),
      skip: 1,
      expect: () => [
        isA<TripState>()
            .having((s) => _orders(s.stops), 'orders', [0, 1, 2])
            .having((s) => s.stops.last.people, 'people', [testPerson]),
      ],
      verify: (_) => expect(routedStops(), hasLength(3)),
    );

    blocTest<TripBloc, TripState>(
      'drops a stale route when a newer request was issued',
      build: () => tripBloc,
      act: (bloc) async {
        final first = Completer<List<LatLng>>();
        final second = Completer<List<LatLng>>();
        final pending = [first, second];
        when(
          () => routingService.getRoute(any()),
        ).thenAnswer((_) => pending.removeAt(0).future);

        bloc.add(AddStop(testPerson));
        bloc.add(AddStop(_person('2', lng: 20)));
        await pumpEventQueue();
        second.complete(route);
        await pumpEventQueue();
        // The first request resolves last and must not overwrite the route.
        first.complete(const [LatLng(9, 9)]);
        await pumpEventQueue();
      },
      verify: (bloc) {
        expect(bloc.state.routePoints, route);
        expect(bloc.state.stops, hasLength(2));
        expect(bloc.state.isOptimizing, isFalse);
      },
    );
  });

  group('AddAirportStop / AddStationStop', () {
    blocTest<TripBloc, TripState>(
      'adds a hub-only airport stop at the airport',
      build: () => tripBloc,
      act: (bloc) => bloc.add(AddAirportStop(ord)),
      expect: () => [
        isA<TripState>()
            .having((s) => s.stops.single.airport, 'airport', same(ord))
            .having((s) => s.stops.single.people, 'people', isEmpty)
            .having(
              (s) => s.stops.single.location,
              'location',
              LatLng(ord.latitude, ord.longitude),
            )
            .having((s) => s.isOptimizing, 'isOptimizing', true),
        isA<TripState>().having((s) => s.routePoints, 'route', route),
      ],
    );

    blocTest<TripBloc, TripState>(
      'adds a hub-only station stop at the station',
      build: () => tripBloc,
      seed: () => TripState(stops: [_stop(0)]),
      act: (bloc) => bloc.add(AddStationStop(union)),
      expect: () => [
        isA<TripState>()
            .having((s) => s.stops.last.station, 'station', same(union))
            .having((s) => s.stops.last.sequenceOrder, 'order', 1)
            .having(
              (s) => s.stops.last.location,
              'location',
              LatLng(union.latitude, union.longitude),
            ),
        isA<TripState>().having((s) => s.isOptimizing, 'isOptimizing', false),
      ],
    );
  });

  group('LinkPersonToStop', () {
    final hubless = _stop(0, lat: 1, lng: 1);
    final airportStop = TripStop(
      airport: ord,
      location: LatLng(ord.latitude, ord.longitude),
      sequenceOrder: 0,
    );

    blocTest<TripBloc, TripState>(
      'ignores an out-of-range stop index',
      build: () => tripBloc,
      seed: () => TripState(stops: [hubless]),
      act: (bloc) => bloc
        ..add(LinkPersonToStop(testPerson, -1))
        ..add(LinkPersonToStop(testPerson, 1)),
      expect: () => <TripState>[],
    );

    blocTest<TripBloc, TripState>(
      'ignores a person already at the stop',
      build: () => tripBloc,
      seed: () => TripState(
        stops: [
          hubless.copyWith(people: [testPerson]),
        ],
      ),
      act: (bloc) => bloc.add(LinkPersonToStop(_person('1', lng: 50), 0)),
      expect: () => <TripState>[],
    );

    blocTest<TripBloc, TripState>(
      'adds the person and adopts their airport when the stop has no hub',
      build: () => tripBloc,
      seed: () => TripState(stops: [hubless]),
      act: (bloc) => bloc.add(LinkPersonToStop(_person('2', airport: ord), 0)),
      expect: () => [
        isA<TripState>()
            .having((s) => s.stops.single.people.map((p) => p.id), 'people', [
              '2',
            ])
            .having((s) => s.stops.single.airport, 'airport', same(ord))
            .having(
              (s) => s.stops.single.location,
              'location',
              LatLng(ord.latitude, ord.longitude),
            ),
      ],
      verify: (_) => verifyNever(() => routingService.getRoute(any())),
    );

    blocTest<TripBloc, TripState>(
      'adopts the station when the person has no airport',
      build: () => tripBloc,
      seed: () => TripState(stops: [hubless]),
      act: (bloc) =>
          bloc.add(LinkPersonToStop(_person('2', station: union), 0)),
      expect: () => [
        isA<TripState>()
            .having((s) => s.stops.single.station, 'station', same(union))
            .having(
              (s) => s.stops.single.location,
              'location',
              LatLng(union.latitude, union.longitude),
            ),
      ],
    );

    blocTest<TripBloc, TripState>(
      'keeps the location when neither the stop nor the person has a hub',
      build: () => tripBloc,
      seed: () => TripState(stops: [hubless]),
      act: (bloc) => bloc.add(LinkPersonToStop(_person('2'), 0)),
      expect: () => [
        isA<TripState>()
            .having((s) => s.stops.single.people.length, 'people', 1)
            .having(
              (s) => s.stops.single.location,
              'location',
              hubless.location,
            )
            .having((s) => s.stops.single.airport, 'airport', isNull),
      ],
    );

    blocTest<TripBloc, TripState>(
      "keeps an existing hub instead of the person's preference",
      build: () => tripBloc,
      seed: () => TripState(stops: [airportStop, _stop(1)]),
      act: (bloc) =>
          bloc.add(LinkPersonToStop(_person('2', station: union), 0)),
      expect: () => [
        isA<TripState>()
            .having((s) => s.stops.first.airport, 'airport', same(ord))
            .having((s) => s.stops.first.station, 'station', isNull)
            .having(
              (s) => s.stops.first.location,
              'location',
              airportStop.location,
            )
            .having((s) => s.stops.first.people.length, 'people', 1)
            .having((s) => s.stops.last, 'other stop', _stop(1)),
      ],
    );
  });

  group('RemoveStop', () {
    blocTest<TripBloc, TripState>(
      'removes the stop, renumbers the rest, and re-routes',
      build: () => tripBloc,
      seed: () => TripState(
        stops: [_stop(0, lng: 0), _stop(1, lng: 1), _stop(2, lng: 2)],
      ),
      act: (bloc) => bloc.add(const RemoveStop(1)),
      expect: () => [
        isA<TripState>()
            .having((s) => _lngs(s.stops), 'lngs', [0, 2])
            .having((s) => _orders(s.stops), 'orders', [0, 1])
            .having((s) => s.isOptimizing, 'isOptimizing', true),
        isA<TripState>()
            .having((s) => s.routePoints, 'route', route)
            .having((s) => s.isOptimizing, 'isOptimizing', false),
      ],
      verify: (_) => expect(_lngs(routedStops()), [0, 2]),
    );
  });

  group('ReorderStops', () {
    final three = [_stop(0, lng: 0), _stop(1, lng: 1), _stop(2, lng: 2)];

    blocTest<TripBloc, TripState>(
      'moving down uses ReorderableListView index semantics',
      build: () => tripBloc,
      seed: () => TripState(stops: three),
      // Drag the first item to the end: newIndex is past the last slot.
      act: (bloc) => bloc.add(const ReorderStops(0, 3)),
      expect: () => [
        isA<TripState>()
            .having((s) => _lngs(s.stops), 'lngs', [1, 2, 0])
            .having((s) => _orders(s.stops), 'orders', [0, 1, 2])
            .having((s) => s.isOptimizing, 'isOptimizing', true),
        isA<TripState>().having((s) => s.routePoints, 'route', route),
      ],
      verify: (_) => expect(_lngs(routedStops()), [1, 2, 0]),
    );

    blocTest<TripBloc, TripState>(
      'moving up inserts at the target index',
      build: () => tripBloc,
      seed: () => TripState(stops: three),
      act: (bloc) => bloc.add(const ReorderStops(2, 0)),
      skip: 1,
      expect: () => [
        isA<TripState>()
            .having((s) => _lngs(s.stops), 'lngs', [2, 0, 1])
            .having((s) => _orders(s.stops), 'orders', [0, 1, 2]),
      ],
    );
  });

  group('ClearTrip', () {
    blocTest<TripBloc, TripState>(
      'resets stops, route and the current trip id',
      build: () => tripBloc,
      seed: () => TripState(
        stops: [_stop(0)],
        routePoints: const [LatLng(0, 0)],
        currentTripId: 'trip-1',
        isOptimizing: true,
      ),
      act: (bloc) => bloc.add(const ClearTrip()),
      expect: () => [const TripState()],
    );

    blocTest<TripBloc, TripState>(
      'keeps saved trips in the list',
      build: () => tripBloc,
      seed: () => TripState(
        stops: [_stop(0)],
        userTrips: [Trip(name: 'Kept', date: DateTime(2026))],
      ),
      act: (bloc) => bloc.add(const ClearTrip()),
      expect: () => [
        TripState(
          userTrips: [Trip(name: 'Kept', date: DateTime(2026))],
        ),
      ],
    );

    blocTest<TripBloc, TripState>(
      'discards a route that arrives after the trip was cleared',
      build: () => tripBloc,
      act: (bloc) async {
        final pending = Completer<List<LatLng>>();
        when(
          () => routingService.getRoute(any()),
        ).thenAnswer((_) => pending.future);
        bloc.add(AddStop(testPerson));
        await pumpEventQueue();
        bloc.add(const ClearTrip());
        await pumpEventQueue();
        pending.complete(route);
        await pumpEventQueue();
      },
      expect: () => [
        isA<TripState>().having((s) => s.isOptimizing, 'isOptimizing', true),
        const TripState(),
      ],
    );
  });

  group('OptimizeTrip', () {
    blocTest<TripBloc, TripState>(
      'does nothing with fewer than three stops',
      build: () => tripBloc,
      seed: () => TripState(stops: [_stop(0), _stop(1, lng: 1)]),
      act: (bloc) => bloc.add(const OptimizeTrip()),
      expect: () => <TripState>[],
      verify: (_) => verifyNever(() => routingService.getRoute(any())),
    );

    blocTest<TripBloc, TripState>(
      'reorders stops into the shortest greedy path and renumbers them',
      build: () => tripBloc,
      // Along the equator: 0, 10, 1, 11 degrees east. The best visiting
      // order is 0 -> 1 -> 10 -> 11.
      seed: () => TripState(
        stops: [
          _stop(0, lng: 0),
          _stop(1, lng: 10),
          _stop(2, lng: 1),
          _stop(3, lng: 11),
        ],
      ),
      act: (bloc) => bloc.add(const OptimizeTrip()),
      expect: () => [
        isA<TripState>()
            .having((s) => s.isOptimizing, 'isOptimizing', true)
            .having((s) => _lngs(s.stops), 'unchanged yet', [0, 10, 1, 11]),
        isA<TripState>()
            .having((s) => _lngs(s.stops), 'lngs', [0, 1, 10, 11])
            .having((s) => _orders(s.stops), 'orders', [0, 1, 2, 3])
            .having((s) => s.routePoints, 'route', route)
            .having((s) => s.isOptimizing, 'isOptimizing', false),
      ],
      verify: (_) => expect(_lngs(routedStops()), [0, 1, 10, 11]),
    );

    blocTest<TripBloc, TripState>(
      'can pick a start other than the first stop',
      build: () => tripBloc,
      // Greedy from the first stop zig-zags (5,4,6,0 = 9 degrees). Starting
      // at the 6 sweeps west (6,5,4,0 = 6), which beats every other start;
      // the 0 start ties at 6 but is tried later, so the first best wins.
      seed: () => TripState(
        stops: [
          _stop(0, lng: 5),
          _stop(1, lng: 4),
          _stop(2, lng: 6),
          _stop(3, lng: 0),
        ],
      ),
      act: (bloc) => bloc.add(const OptimizeTrip()),
      skip: 1,
      expect: () => [
        isA<TripState>()
            .having((s) => _lngs(s.stops), 'lngs', [6, 5, 4, 0])
            .having((s) => _orders(s.stops), 'orders', [0, 1, 2, 3]),
      ],
    );
  });

  group('UpdateLegDetails', () {
    const legA = TripLeg(
      id: 'leg-a',
      departureStopId: 's1',
      arrivalStopId: 's2',
    );
    const legB = TripLeg(departureStopId: 's2', arrivalStopId: 's3');

    blocTest<TripBloc, TripState>(
      'replaces the leg with the same id',
      build: () => tripBloc,
      seed: () => const TripState(legs: [legA, legB]),
      act: (bloc) => bloc.add(
        const UpdateLegDetails(
          TripLeg(
            id: 'leg-a',
            departureStopId: 'x',
            arrivalStopId: 'y',
            transportType: 'FLIGHT',
          ),
        ),
      ),
      expect: () => [
        const TripState(
          legs: [
            TripLeg(
              id: 'leg-a',
              departureStopId: 'x',
              arrivalStopId: 'y',
              transportType: 'FLIGHT',
            ),
            legB,
          ],
        ),
      ],
    );

    blocTest<TripBloc, TripState>(
      'matches an unsaved leg by its departure and arrival stops',
      build: () => tripBloc,
      seed: () => const TripState(legs: [legA, legB]),
      act: (bloc) =>
          bloc.add(UpdateLegDetails(legB.copyWith(bookingReference: 'ABC123'))),
      expect: () => [
        TripState(
          legs: [
            legA,
            legB.copyWith(bookingReference: 'ABC123'),
          ],
        ),
      ],
    );

    blocTest<TripBloc, TripState>(
      'leaves the legs alone when nothing matches',
      build: () => tripBloc,
      seed: () => const TripState(legs: [legA, legB]),
      act: (bloc) => bloc.add(
        const UpdateLegDetails(
          TripLeg(departureStopId: 'zz', arrivalStopId: 'yy'),
        ),
      ),
      // Same content, so the emit is deduplicated away.
      expect: () => <TripState>[],
    );
  });

  group('SaveTrip', () {
    final stops = [_stop(0, id: 's1'), _stop(1, lng: 1, id: 's2')];
    const legs = [TripLeg(departureStopId: 's1', arrivalStopId: 's2')];
    final start = DateTime(2026, 8, 1);
    final end = DateTime(2026, 8, 3);

    blocTest<TripBloc, TripState>(
      'creates a new trip from the current stops, then refreshes the list',
      build: () {
        final savedTrip = Trip(
          id: '123',
          name: 'Saved',
          date: start,
          stops: stops,
          legs: const [
            TripLeg(id: 'leg-1', departureStopId: 's1', arrivalStopId: 's2'),
          ],
        );
        when(
          () => apiService.createTrip(any()),
        ).thenAnswer((_) async => savedTrip);
        when(() => apiService.getTrips()).thenAnswer((_) async => [savedTrip]);
        return tripBloc;
      },
      seed: () => TripState(stops: stops, legs: legs, error: 'old error'),
      act: (bloc) => bloc.add(
        SaveTrip(
          name: 'Summer',
          startDate: start,
          endDate: end,
          status: TripStatus.booked,
        ),
      ),
      expect: () => [
        TripState(stops: stops, legs: legs, isLoading: true),
        isA<TripState>()
            .having((s) => s.isLoading, 'isLoading', false)
            .having((s) => s.currentTripId, 'currentTripId', '123')
            .having((s) => s.legs.single.id, 'saved leg id', 'leg-1'),
        isA<TripState>()
            .having((s) => s.isLoading, 'isLoading', true)
            .having((s) => s.currentTripId, 'currentTripId', '123'),
        isA<TripState>()
            .having((s) => s.isLoading, 'isLoading', false)
            .having((s) => s.userTrips.single.id, 'userTrips', '123'),
      ],
      verify: (_) {
        final sent =
            verify(() => apiService.createTrip(captureAny())).captured.single
                as Trip;
        expect(sent.id, isNull);
        expect(sent.name, 'Summer');
        expect(sent.date, start);
        expect(sent.startDate, start);
        expect(sent.endDate, end);
        expect(sent.status, TripStatus.booked);
        expect(sent.stops, stops);
        expect(sent.legs, legs);
        verifyNever(() => apiService.updateTrip(any()));
        verify(() => apiService.getTrips()).called(1);
      },
    );

    blocTest<TripBloc, TripState>(
      'updates the loaded trip instead of creating a new one',
      build: () {
        when(
          () => apiService.updateTrip(any()),
        ).thenAnswer((inv) async => inv.positionalArguments.first as Trip);
        when(() => apiService.getTrips()).thenAnswer((_) async => []);
        return tripBloc;
      },
      seed: () => TripState(stops: stops, currentTripId: 'trip-9'),
      act: (bloc) =>
          bloc.add(const SaveTrip(name: 'Renamed', status: TripStatus.draft)),
      verify: (bloc) {
        final sent =
            verify(() => apiService.updateTrip(captureAny())).captured.single
                as Trip;
        expect(sent.id, 'trip-9');
        expect(sent.name, 'Renamed');
        expect(sent.startDate, isNull);
        // Without a start date the legacy date defaults to "now".
        expect(
          sent.date.difference(DateTime.now()).inMinutes.abs(),
          lessThan(1),
        );
        verifyNever(() => apiService.createTrip(any()));
        expect(bloc.state.currentTripId, 'trip-9');
        expect(bloc.state.isLoading, isFalse);
      },
    );

    blocTest<TripBloc, TripState>(
      'reports a failure and does not refresh the list',
      build: () {
        when(
          () => apiService.createTrip(any()),
        ).thenThrow(Exception('Failed to create trip'));
        return tripBloc;
      },
      seed: () => TripState(stops: stops),
      act: (bloc) =>
          bloc.add(const SaveTrip(name: 'X', status: TripStatus.draft)),
      expect: () => [
        TripState(stops: stops, isLoading: true),
        TripState(stops: stops, error: 'Exception: Failed to create trip'),
      ],
      verify: (_) => verifyNever(() => apiService.getTrips()),
    );
  });

  group('UpdateTripStatus', () {
    final saved = Trip(
      id: 'saved-1',
      name: 'Road Trip',
      date: DateTime(2026, 8, 1),
      startDate: DateTime(2026, 8, 1),
      stops: [
        _stop(0, lat: 1, lng: 1, id: 's1'),
        _stop(1, lat: 2, lng: 2),
      ],
    );
    final plannerStops = [_stop(0, lat: 9, lng: 9)];

    blocTest<TripBloc, TripState>(
      'updates that trip by id, not the one open in the planner',
      build: () {
        when(
          () => apiService.updateTrip(any()),
        ).thenAnswer((inv) async => inv.positionalArguments.first as Trip);
        when(() => apiService.getTrips()).thenAnswer((_) async => [saved]);
        return tripBloc;
      },
      // A different, unsaved trip is open in the planner.
      seed: () => TripState(stops: plannerStops),
      act: (bloc) => bloc.add(UpdateTripStatus(saved, TripStatus.booked)),
      verify: (bloc) {
        final sent =
            verify(() => apiService.updateTrip(captureAny())).captured.single
                as Trip;
        expect(sent, saved.copyWith(status: TripStatus.booked));
        verifyNever(() => apiService.createTrip(any()));
        verify(() => apiService.getTrips()).called(1);
        expect(bloc.state.stops, plannerStops);
        expect(bloc.state.currentTripId, isNull);
        expect(bloc.state.userTrips, [saved]);
      },
    );

    blocTest<TripBloc, TripState>(
      'reports a failure and keeps the planner',
      build: () {
        when(
          () => apiService.updateTrip(any()),
        ).thenThrow(Exception('Failed to update trip'));
        return tripBloc;
      },
      seed: () => TripState(stops: plannerStops, currentTripId: 'other'),
      act: (bloc) => bloc.add(UpdateTripStatus(saved, TripStatus.booked)),
      expect: () => [
        TripState(stops: plannerStops, currentTripId: 'other', isLoading: true),
        TripState(
          stops: plannerStops,
          currentTripId: 'other',
          error: 'Exception: Failed to update trip',
        ),
      ],
      verify: (_) => verifyNever(() => apiService.getTrips()),
    );
  });

  group('FetchUserTrips', () {
    blocTest<TripBloc, TripState>(
      'emits [isLoading: true, isLoading: false] with trips',
      build: () {
        when(() => apiService.getTrips()).thenAnswer(
          (_) async => [Trip(id: 't', name: 'T', date: DateTime(2026))],
        );
        return tripBloc;
      },
      act: (bloc) => bloc.add(const FetchUserTrips()),
      expect: () => [
        const TripState(isLoading: true),
        TripState(
          userTrips: [Trip(id: 't', name: 'T', date: DateTime(2026))],
        ),
      ],
    );

    blocTest<TripBloc, TripState>(
      'clears an old error and reports a new one',
      build: () {
        when(
          () => apiService.getTrips(),
        ).thenThrow(Exception('Failed to load trips'));
        return tripBloc;
      },
      seed: () => const TripState(error: 'stale'),
      act: (bloc) => bloc.add(const FetchUserTrips()),
      expect: () => [
        const TripState(isLoading: true),
        const TripState(error: 'Exception: Failed to load trips'),
      ],
    );
  });

  group('LoadTrip', () {
    final trip = Trip(
      id: '456',
      name: 'Existing',
      date: DateTime(2026),
      stops: [_stop(0, lat: 1, lng: 1)],
      legs: const [TripLeg(departureStopId: 'a', arrivalStopId: 'b')],
    );

    blocTest<TripBloc, TripState>(
      'loads stops and legs, then fetches the route',
      build: () => tripBloc,
      seed: () => const TripState(error: 'stale'),
      act: (bloc) => bloc.add(LoadTrip(trip)),
      expect: () => [
        TripState(
          isLoading: true,
          stops: trip.stops,
          legs: trip.legs,
          currentTripId: '456',
        ),
        TripState(
          stops: trip.stops,
          legs: trip.legs,
          currentTripId: '456',
          routePoints: route,
        ),
      ],
      verify: (_) => expect(routedStops(), trip.stops),
    );

    blocTest<TripBloc, TripState>(
      'drops the route of a trip that was cleared while routing',
      build: () => tripBloc,
      act: (bloc) async {
        final pending = Completer<List<LatLng>>();
        when(
          () => routingService.getRoute(any()),
        ).thenAnswer((_) => pending.future);
        bloc.add(LoadTrip(trip));
        await pumpEventQueue();
        bloc.add(const ClearTrip());
        await pumpEventQueue();
        pending.complete(route);
        await pumpEventQueue();
      },
      verify: (bloc) {
        expect(bloc.state.routePoints, isEmpty);
        expect(bloc.state.stops, isEmpty);
        expect(bloc.state.currentTripId, isNull);
      },
    );
  });

  group('DeleteTrip', () {
    final remaining = [Trip(id: 'other', name: 'Other', date: DateTime(2026))];

    blocTest<TripBloc, TripState>(
      'deleting the open trip clears it and refreshes the list',
      build: () {
        when(() => apiService.deleteTrip('trip-1')).thenAnswer((_) async {});
        when(() => apiService.getTrips()).thenAnswer((_) async => remaining);
        return tripBloc;
      },
      seed: () => TripState(stops: [_stop(0)], currentTripId: 'trip-1'),
      act: (bloc) => bloc.add(const DeleteTrip('trip-1')),
      expect: () => [
        TripState(stops: [_stop(0)], currentTripId: 'trip-1', isLoading: true),
        const TripState(isLoading: true),
        TripState(userTrips: remaining),
      ],
      verify: (_) {
        verify(() => apiService.deleteTrip('trip-1')).called(1);
        verify(() => apiService.getTrips()).called(1);
      },
    );

    blocTest<TripBloc, TripState>(
      'deleting another trip keeps the open one',
      build: () {
        when(() => apiService.deleteTrip('trip-2')).thenAnswer((_) async {});
        when(() => apiService.getTrips()).thenAnswer((_) async => remaining);
        return tripBloc;
      },
      seed: () => TripState(stops: [_stop(0)], currentTripId: 'trip-1'),
      act: (bloc) => bloc.add(const DeleteTrip('trip-2')),
      expect: () => [
        TripState(stops: [_stop(0)], currentTripId: 'trip-1', isLoading: true),
        TripState(
          stops: [_stop(0)],
          currentTripId: 'trip-1',
          userTrips: remaining,
        ),
      ],
    );

    blocTest<TripBloc, TripState>(
      'reports a failure and keeps the open trip',
      build: () {
        when(
          () => apiService.deleteTrip(any()),
        ).thenThrow(Exception('Failed to delete trip'));
        return tripBloc;
      },
      seed: () => const TripState(currentTripId: 'trip-1'),
      act: (bloc) => bloc.add(const DeleteTrip('trip-1')),
      expect: () => [
        const TripState(currentTripId: 'trip-1', isLoading: true),
        const TripState(
          currentTripId: 'trip-1',
          error: 'Exception: Failed to delete trip',
        ),
      ],
      verify: (_) => verifyNever(() => apiService.getTrips()),
    );
  });

  test('trip events have value equality', () {
    expect(AddStop(testPerson), AddStop(testPerson));
    expect(AddAirportStop(ord), AddAirportStop(ord));
    expect(AddStationStop(union), AddStationStop(union));
    expect(
      LinkPersonToStop(testPerson, 0),
      isNot(LinkPersonToStop(testPerson, 1)),
    );
    expect(const RemoveStop(1), const RemoveStop(1));
    expect(const ReorderStops(0, 1), isNot(const ReorderStops(1, 0)));
    expect(const OptimizeTrip(), const OptimizeTrip());
    expect(
      const SaveTrip(name: 'a', status: TripStatus.draft),
      isNot(const SaveTrip(name: 'a', status: TripStatus.booked)),
    );
    expect(
      const UpdateLegDetails(TripLeg(departureStopId: 'a', arrivalStopId: 'b')),
      const UpdateLegDetails(TripLeg(departureStopId: 'a', arrivalStopId: 'b')),
    );
    final trip = Trip(name: 't', date: DateTime(2026));
    expect(LoadTrip(trip), LoadTrip(trip));
    expect(const DeleteTrip('a'), isNot(const DeleteTrip('b')));
  });
}
