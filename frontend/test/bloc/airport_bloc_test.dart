import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/airport/airport_event.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/services/airport_service.dart';

class MockAirportService extends Mock implements AirportService {}

void main() {
  late MockAirportService service;

  final ord = Airport(
    name: "O'Hare International",
    iataCode: 'ORD',
    airportType: 'large_airport',
    city: 'Chicago',
    country: 'US',
    latitude: 41.9786,
    longitude: -87.9048,
  );
  final mdw = Airport(
    name: 'Midway International',
    iataCode: 'MDW',
    airportType: 'large_airport',
    city: 'Chicago',
    country: 'US',
    latitude: 41.7868,
    longitude: -87.7522,
  );

  setUp(() {
    service = MockAirportService();
  });

  test('initial state is AirportInitial', () {
    final bloc = AirportBloc(airportService: service);
    expect(bloc.state, AirportInitial());
    bloc.close();
  });

  group('LoadMapAirports', () {
    blocTest<AirportBloc, AirportState>(
      'emits [AirportLoading, MapAirportsLoaded] with the bundled airports',
      build: () {
        when(
          () => service.loadAirportsFromAsset(),
        ).thenAnswer((_) async => [ord, mdw]);
        return AirportBloc(airportService: service);
      },
      act: (bloc) => bloc.add(LoadMapAirports()),
      expect: () => [
        AirportLoading(),
        MapAirportsLoaded([ord, mdw]),
      ],
      verify: (_) {
        verify(() => service.loadAirportsFromAsset()).called(1);
        verifyNever(
          () => service.getNearestAirports(
            any(),
            any(),
            count: any(named: 'count'),
          ),
        );
      },
    );

    blocTest<AirportBloc, AirportState>(
      'emits [AirportLoading, AirportError] when the asset cannot be read',
      build: () {
        when(
          () => service.loadAirportsFromAsset(),
        ).thenThrow(Exception('asset missing'));
        return AirportBloc(airportService: service);
      },
      act: (bloc) => bloc.add(LoadMapAirports()),
      expect: () => [
        AirportLoading(),
        const AirportError('Exception: asset missing'),
      ],
    );
  });

  group('LoadNearestAirports', () {
    blocTest<AirportBloc, AirportState>(
      'passes the coordinate and count through and emits the result',
      build: () {
        when(
          () => service.getNearestAirports(41.88, -87.63, count: 5),
        ).thenAnswer((_) async => [mdw, ord]);
        return AirportBloc(airportService: service);
      },
      act: (bloc) => bloc.add(
        const LoadNearestAirports(latitude: 41.88, longitude: -87.63, count: 5),
      ),
      expect: () => [
        AirportLoading(),
        NearestAirportsLoaded([mdw, ord]),
      ],
      verify: (_) {
        verify(
          () => service.getNearestAirports(41.88, -87.63, count: 5),
        ).called(1);
      },
    );

    blocTest<AirportBloc, AirportState>(
      'defaults the count to 3',
      build: () {
        when(
          () => service.getNearestAirports(any(), any(), count: 3),
        ).thenAnswer((_) async => []);
        return AirportBloc(airportService: service);
      },
      act: (bloc) =>
          bloc.add(const LoadNearestAirports(latitude: 1, longitude: 2)),
      expect: () => [AirportLoading(), const NearestAirportsLoaded([])],
      verify: (_) {
        verify(() => service.getNearestAirports(1, 2, count: 3)).called(1);
      },
    );

    blocTest<AirportBloc, AirportState>(
      'emits [AirportLoading, AirportError] when the lookup fails',
      build: () {
        when(
          () => service.getNearestAirports(
            any(),
            any(),
            count: any(named: 'count'),
          ),
        ).thenThrow(Exception('Failed to load nearest airports'));
        return AirportBloc(airportService: service);
      },
      act: (bloc) =>
          bloc.add(const LoadNearestAirports(latitude: 1, longitude: 2)),
      expect: () => [
        AirportLoading(),
        const AirportError('Exception: Failed to load nearest airports'),
      ],
    );
  });

  test('nearest-airport events compare by coordinate and count', () {
    expect(
      const LoadNearestAirports(latitude: 1, longitude: 2),
      const LoadNearestAirports(latitude: 1, longitude: 2, count: 3),
    );
    expect(
      const LoadNearestAirports(latitude: 1, longitude: 2),
      isNot(const LoadNearestAirports(latitude: 1, longitude: 2, count: 4)),
    );
    expect(LoadMapAirports(), LoadMapAirports());
  });
}
