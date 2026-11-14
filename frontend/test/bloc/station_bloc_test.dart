import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/bloc/station/station_event.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/services/station_service.dart';

class MockStationService extends Mock implements StationService {}

void main() {
  late MockStationService service;

  final union = Station(
    name: 'Union Station',
    osmId: 101,
    stationType: 'major_station',
    city: 'Chicago',
    country: 'USA',
    latitude: 41.8789,
    longitude: -87.6400,
  );
  final ogilvie = Station(
    name: 'Ogilvie',
    osmId: 102,
    stationType: 'commuter_station',
    latitude: 41.8826,
    longitude: -87.6406,
  );

  setUp(() {
    service = MockStationService();
  });

  test('initial state is StationInitial', () {
    final bloc = StationBloc(stationService: service);
    expect(bloc.state, StationInitial());
    bloc.close();
  });

  group('LoadMapStations', () {
    blocTest<StationBloc, StationState>(
      'emits [StationLoading, MapStationsLoaded] with the bundled stations',
      build: () {
        when(
          () => service.loadStationsFromAsset(),
        ).thenAnswer((_) async => [union, ogilvie]);
        return StationBloc(stationService: service);
      },
      act: (bloc) => bloc.add(LoadMapStations()),
      expect: () => [
        StationLoading(),
        MapStationsLoaded([union, ogilvie]),
      ],
      verify: (_) {
        verify(() => service.loadStationsFromAsset()).called(1);
      },
    );

    blocTest<StationBloc, StationState>(
      'emits [StationLoading, StationError] when the asset cannot be read',
      build: () {
        when(
          () => service.loadStationsFromAsset(),
        ).thenThrow(const FormatException('bad json'));
        return StationBloc(stationService: service);
      },
      act: (bloc) => bloc.add(LoadMapStations()),
      expect: () => [
        StationLoading(),
        const StationError('FormatException: bad json'),
      ],
    );
  });

  group('FetchNearestStations', () {
    blocTest<StationBloc, StationState>(
      'passes the coordinate and count through and emits the result',
      build: () {
        when(
          () => service.getNearestStations(41.88, -87.63, count: 7),
        ).thenAnswer((_) async => [ogilvie, union]);
        return StationBloc(stationService: service);
      },
      act: (bloc) => bloc.add(
        const FetchNearestStations(
          latitude: 41.88,
          longitude: -87.63,
          count: 7,
        ),
      ),
      expect: () => [
        StationLoading(),
        NearestStationsLoaded([ogilvie, union]),
      ],
      verify: (_) {
        verify(
          () => service.getNearestStations(41.88, -87.63, count: 7),
        ).called(1);
        verifyNever(() => service.loadStationsFromAsset());
      },
    );

    blocTest<StationBloc, StationState>(
      'defaults the count to 3',
      build: () {
        when(
          () => service.getNearestStations(any(), any(), count: 3),
        ).thenAnswer((_) async => []);
        return StationBloc(stationService: service);
      },
      act: (bloc) =>
          bloc.add(const FetchNearestStations(latitude: 1, longitude: 2)),
      expect: () => [StationLoading(), const NearestStationsLoaded([])],
      verify: (_) {
        verify(() => service.getNearestStations(1, 2, count: 3)).called(1);
      },
    );

    blocTest<StationBloc, StationState>(
      'emits [StationLoading, StationError] when the lookup fails',
      build: () {
        when(
          () => service.getNearestStations(
            any(),
            any(),
            count: any(named: 'count'),
          ),
        ).thenThrow(Exception('Failed to load nearest stations'));
        return StationBloc(stationService: service);
      },
      act: (bloc) =>
          bloc.add(const FetchNearestStations(latitude: 1, longitude: 2)),
      expect: () => [
        StationLoading(),
        const StationError('Exception: Failed to load nearest stations'),
      ],
    );
  });

  test('nearest-station events compare by coordinate and count', () {
    expect(
      const FetchNearestStations(latitude: 1, longitude: 2),
      const FetchNearestStations(latitude: 1, longitude: 2, count: 3),
    );
    expect(
      const FetchNearestStations(latitude: 1, longitude: 2),
      isNot(const FetchNearestStations(latitude: 1, longitude: 3)),
    );
    expect(LoadMapStations(), LoadMapStations());
  });
}
