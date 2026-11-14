import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/bloc/station/station_event.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/components/shared/nearby_blocs.dart';
import 'package:map_my_friends/components/shared/nearby_stations_section.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:mocktail/mocktail.dart';

class MockStationBloc extends MockBloc<StationEvent, StationState>
    implements StationBloc {}

class MockAirportBloc extends Mock implements AirportBloc {}

class MockMapSettingsCubit extends MockCubit<MapSettingsState>
    implements MapSettingsCubit {}

Station _station({
  String name = 'Union Station',
  String? city = 'Chicago',
  String? country = 'USA',
  double? distanceKm = 3,
}) => Station(
  name: name,
  osmId: 1,
  stationType: 'major_station',
  city: city,
  country: country,
  latitude: 41.87,
  longitude: -87.64,
  distanceKm: distanceKm,
);

void main() {
  late MockMapSettingsCubit settings;

  setUpAll(() {
    registerFallbackValue(
      const FetchNearestStations(latitude: 0, longitude: 0),
    );
  });

  setUp(() {
    settings = MockMapSettingsCubit();
    when(() => settings.state).thenReturn(const MapSettingsState());
  });

  Widget host(Widget child, {NearbyBlocs? nearby}) {
    Widget body = Scaffold(body: SingleChildScrollView(child: child));
    if (nearby != null) {
      body = RepositoryProvider<NearbyBlocs>.value(value: nearby, child: body);
    }
    return BlocProvider<MapSettingsCubit>.value(
      value: settings,
      child: MaterialApp(home: body),
    );
  }

  group('with a provided NearbyBlocs', () {
    late MockStationBloc stations;
    late NearbyBlocs nearby;

    setUp(() {
      stations = MockStationBloc();
      nearby = NearbyBlocs(airports: MockAirportBloc(), stations: stations);
    });

    testWidgets('shows a pulse while loading', (tester) async {
      when(() => stations.state).thenReturn(StationLoading());

      await tester.pumpWidget(
        host(
          const NearbyStationsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );

      expect(find.byType(PulseIndicator), findsOneWidget);
      expect(find.text('Nearby Train Stations'), findsNothing);
    });

    testWidgets('lists each station with its place and distance', (
      tester,
    ) async {
      when(() => stations.state).thenReturn(
        NearestStationsLoaded([
          _station(),
          _station(
            name: 'Gare du Nord',
            city: '',
            country: 'France',
            distanceKm: null,
          ),
          _station(name: 'Nowhere Halt', city: null, country: null),
        ]),
      );

      await tester.pumpWidget(
        host(
          const NearbyStationsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );

      expect(find.text('Nearby Train Stations'), findsOneWidget);
      expect(find.text('Union Station'), findsOneWidget);
      expect(find.text('Chicago'), findsOneWidget);
      // Empty city falls back to the country...
      expect(find.text('Gare du Nord'), findsOneWidget);
      expect(find.text('France'), findsOneWidget);
      // ...and with neither, to the product's home market.
      expect(find.text('Nowhere Halt'), findsOneWidget);
      expect(find.text('USA'), findsOneWidget);
      // Two stations carry a distance, the third does not.
      expect(find.text('3 km'), findsNWidgets(2));
    });

    testWidgets('formats the distance in the chosen unit', (tester) async {
      when(
        () => settings.state,
      ).thenReturn(const MapSettingsState(distanceUnit: DistanceUnit.imperial));
      when(
        () => stations.state,
      ).thenReturn(NearestStationsLoaded([_station(distanceKm: 8.05)]));

      await tester.pumpWidget(
        host(
          const NearbyStationsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );

      expect(find.text('5 mi'), findsOneWidget);
    });

    testWidgets('renders nothing for an empty result or an error', (
      tester,
    ) async {
      when(() => stations.state).thenReturn(const NearestStationsLoaded([]));
      await tester.pumpWidget(
        host(
          const NearbyStationsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );
      expect(find.text('Nearby Train Stations'), findsNothing);

      final errored = MockStationBloc();
      when(() => errored.state).thenReturn(const StationError('down'));
      await tester.pumpWidget(
        host(
          const NearbyStationsSection(latitude: 1, longitude: 2),
          nearby: NearbyBlocs(airports: MockAirportBloc(), stations: errored),
        ),
      );
      expect(find.text('Nearby Train Stations'), findsNothing);
      expect(find.byType(PulseIndicator), findsNothing);
      expect(find.textContaining('down'), findsNothing);
    });

    testWidgets('neither loads nor closes a provided bloc', (tester) async {
      when(() => stations.state).thenReturn(StationInitial());

      await tester.pumpWidget(
        host(
          const NearbyStationsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );
      await tester.pumpWidget(
        host(
          const NearbyStationsSection(latitude: 3, longitude: 4),
          nearby: nearby,
        ),
      );
      await tester.pumpWidget(const SizedBox());

      verifyNever(() => stations.add(any()));
      verifyNever(() => stations.close());
    });
  });

  group('with its own bloc', () {
    late MockStationBloc own;
    late int created;

    setUp(() {
      own = MockStationBloc();
      created = 0;
      when(() => own.state).thenReturn(StationInitial());
    });

    StationBloc factory() {
      created++;
      return own;
    }

    testWidgets('loads the three nearest stations to the coordinate', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          NearbyStationsSection(
            latitude: 48.85,
            longitude: 2.35,
            createBloc: factory,
          ),
        ),
      );
      await tester.pumpWidget(
        host(
          NearbyStationsSection(
            latitude: 48.85,
            longitude: 2.35,
            createBloc: factory,
          ),
        ),
      );

      expect(created, 1);
      verify(
        () => own.add(
          const FetchNearestStations(
            latitude: 48.85,
            longitude: 2.35,
            count: 3,
          ),
        ),
      ).called(1);
    });

    testWidgets('reloads when the coordinate changes', (tester) async {
      await tester.pumpWidget(
        host(
          NearbyStationsSection(latitude: 1, longitude: 2, createBloc: factory),
        ),
      );
      await tester.pumpWidget(
        host(
          NearbyStationsSection(latitude: 9, longitude: 2, createBloc: factory),
        ),
      );
      await tester.pumpWidget(
        host(
          NearbyStationsSection(latitude: 9, longitude: 8, createBloc: factory),
        ),
      );

      expect(created, 1);
      verifyInOrder([
        () => own.add(const FetchNearestStations(latitude: 1, longitude: 2)),
        () => own.add(const FetchNearestStations(latitude: 9, longitude: 2)),
        () => own.add(const FetchNearestStations(latitude: 9, longitude: 8)),
      ]);
    });

    testWidgets('renders the state of its own bloc', (tester) async {
      final controller = StreamController<StationState>();
      addTearDown(controller.close);
      whenListen(own, controller.stream, initialState: StationLoading());

      await tester.pumpWidget(
        host(
          NearbyStationsSection(latitude: 1, longitude: 2, createBloc: factory),
        ),
      );
      expect(find.byType(PulseIndicator), findsOneWidget);

      controller.add(NearestStationsLoaded([_station(name: 'Penn Station')]));
      await tester.pump();
      expect(find.text('Penn Station'), findsOneWidget);
      expect(find.byType(PulseIndicator), findsNothing);
    });

    testWidgets('closes its own bloc when disposed', (tester) async {
      await tester.pumpWidget(
        host(
          NearbyStationsSection(latitude: 1, longitude: 2, createBloc: factory),
        ),
      );
      await tester.pumpWidget(const SizedBox());

      verify(() => own.close()).called(1);
    });

    testWidgets('ignores its factory when NearbyBlocs is provided', (
      tester,
    ) async {
      final provided = MockStationBloc();
      when(() => provided.state).thenReturn(StationInitial());

      await tester.pumpWidget(
        host(
          NearbyStationsSection(latitude: 1, longitude: 2, createBloc: factory),
          nearby: NearbyBlocs(airports: MockAirportBloc(), stations: provided),
        ),
      );

      expect(created, 0);
      verifyNever(() => provided.add(any()));
    });
  });
}
