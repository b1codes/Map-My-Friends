import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/airport/airport_event.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/components/shared/nearby_airports_section.dart';
import 'package:map_my_friends/components/shared/nearby_blocs.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:mocktail/mocktail.dart';

class MockAirportBloc extends MockBloc<AirportEvent, AirportState>
    implements AirportBloc {}

class MockStationBloc extends Mock implements StationBloc {}

class MockMapSettingsCubit extends MockCubit<MapSettingsState>
    implements MapSettingsCubit {}

Airport _airport({
  String iata = 'SFO',
  String name = 'San Francisco International',
  String city = 'San Francisco',
  String country = 'USA',
  double? distanceKm = 10,
}) => Airport(
  name: name,
  iataCode: iata,
  airportType: 'large_airport',
  city: city,
  country: country,
  latitude: 37.6,
  longitude: -122.4,
  distanceKm: distanceKm,
);

void main() {
  late MockMapSettingsCubit settings;

  setUpAll(() {
    registerFallbackValue(const LoadNearestAirports(latitude: 0, longitude: 0));
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
    late MockAirportBloc airports;
    late NearbyBlocs nearby;

    setUp(() {
      airports = MockAirportBloc();
      nearby = NearbyBlocs(airports: airports, stations: MockStationBloc());
    });

    testWidgets('shows a pulse while loading', (tester) async {
      when(() => airports.state).thenReturn(AirportLoading());

      await tester.pumpWidget(
        host(
          const NearbyAirportsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );

      expect(find.byType(PulseIndicator), findsOneWidget);
      expect(find.text('Nearby Airports'), findsNothing);
    });

    testWidgets('lists each airport with code, name, place and distance', (
      tester,
    ) async {
      when(() => airports.state).thenReturn(
        NearestAirportsLoaded([
          _airport(),
          _airport(
            iata: 'OAK',
            name: 'Oakland International',
            city: '',
            country: 'United States',
            distanceKm: null,
          ),
        ]),
      );

      await tester.pumpWidget(
        host(
          const NearbyAirportsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );

      expect(find.text('Nearby Airports'), findsOneWidget);
      expect(find.text('SFO'), findsOneWidget);
      expect(find.text('San Francisco International'), findsOneWidget);
      expect(find.text('San Francisco'), findsOneWidget);
      expect(find.text('10 km'), findsOneWidget);
      // An empty city falls back to the country, and no distance means no
      // distance badge.
      expect(find.text('OAK'), findsOneWidget);
      expect(find.text('United States'), findsOneWidget);
      expect(find.textContaining(' km'), findsOneWidget);
    });

    testWidgets('formats the distance in the chosen unit', (tester) async {
      when(
        () => settings.state,
      ).thenReturn(const MapSettingsState(distanceUnit: DistanceUnit.imperial));
      when(
        () => airports.state,
      ).thenReturn(NearestAirportsLoaded([_airport(distanceKm: 16.1)]));

      await tester.pumpWidget(
        host(
          const NearbyAirportsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );

      expect(find.text('10 mi'), findsOneWidget);
      expect(find.textContaining('km'), findsNothing);
    });

    testWidgets('renders nothing for an empty result', (tester) async {
      when(() => airports.state).thenReturn(const NearestAirportsLoaded([]));

      await tester.pumpWidget(
        host(
          const NearbyAirportsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );

      expect(find.text('Nearby Airports'), findsNothing);
      expect(find.byType(PulseIndicator), findsNothing);
    });

    testWidgets('renders nothing on error', (tester) async {
      when(() => airports.state).thenReturn(const AirportError('boom'));

      await tester.pumpWidget(
        host(
          const NearbyAirportsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );

      expect(find.text('Nearby Airports'), findsNothing);
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('neither loads nor closes a provided bloc', (tester) async {
      when(() => airports.state).thenReturn(AirportInitial());

      await tester.pumpWidget(
        host(
          const NearbyAirportsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );
      // Moving the coordinate does not reload a bloc the section does not own.
      await tester.pumpWidget(
        host(
          const NearbyAirportsSection(latitude: 3, longitude: 4),
          nearby: nearby,
        ),
      );
      await tester.pumpWidget(const SizedBox());

      verifyNever(() => airports.add(any()));
      verifyNever(() => airports.close());
    });

    testWidgets('follows the bloc into a loaded state', (tester) async {
      whenListen(
        airports,
        Stream<AirportState>.fromIterable([
          NearestAirportsLoaded([_airport()]),
        ]),
        initialState: AirportLoading(),
      );

      await tester.pumpWidget(
        host(
          const NearbyAirportsSection(latitude: 1, longitude: 2),
          nearby: nearby,
        ),
      );
      expect(find.byType(PulseIndicator), findsOneWidget);

      await tester.pump();
      expect(find.byType(PulseIndicator), findsNothing);
      expect(find.text('SFO'), findsOneWidget);
    });
  });

  group('with its own bloc', () {
    late MockAirportBloc own;
    late int created;

    setUp(() {
      own = MockAirportBloc();
      created = 0;
      when(() => own.state).thenReturn(AirportInitial());
    });

    AirportBloc factory() {
      created++;
      return own;
    }

    testWidgets('creates one bloc and loads the given coordinate', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          NearbyAirportsSection(
            latitude: 51.5,
            longitude: -0.12,
            createBloc: factory,
          ),
        ),
      );
      // Rebuilding with the same coordinate keeps the same bloc.
      await tester.pumpWidget(
        host(
          NearbyAirportsSection(
            latitude: 51.5,
            longitude: -0.12,
            createBloc: factory,
          ),
        ),
      );

      expect(created, 1);
      verify(
        () => own.add(
          const LoadNearestAirports(latitude: 51.5, longitude: -0.12),
        ),
      ).called(1);
    });

    testWidgets('reloads when the coordinate changes', (tester) async {
      await tester.pumpWidget(
        host(
          NearbyAirportsSection(latitude: 1, longitude: 2, createBloc: factory),
        ),
      );
      await tester.pumpWidget(
        host(
          NearbyAirportsSection(latitude: 1, longitude: 5, createBloc: factory),
        ),
      );
      await tester.pumpWidget(
        host(
          NearbyAirportsSection(latitude: 7, longitude: 5, createBloc: factory),
        ),
      );

      expect(created, 1);
      verifyInOrder([
        () => own.add(const LoadNearestAirports(latitude: 1, longitude: 2)),
        () => own.add(const LoadNearestAirports(latitude: 1, longitude: 5)),
        () => own.add(const LoadNearestAirports(latitude: 7, longitude: 5)),
      ]);
    });

    testWidgets('renders the state of its own bloc', (tester) async {
      final controller = StreamController<AirportState>();
      addTearDown(controller.close);
      whenListen(own, controller.stream, initialState: AirportLoading());

      await tester.pumpWidget(
        host(
          NearbyAirportsSection(latitude: 1, longitude: 2, createBloc: factory),
        ),
      );
      expect(find.byType(PulseIndicator), findsOneWidget);

      controller.add(NearestAirportsLoaded([_airport(iata: 'LHR')]));
      await tester.pump();
      expect(find.text('LHR'), findsOneWidget);

      controller.add(const AirportError('offline'));
      await tester.pump();
      expect(find.text('LHR'), findsNothing);
      expect(find.text('Nearby Airports'), findsNothing);
    });

    testWidgets('closes its own bloc when disposed', (tester) async {
      await tester.pumpWidget(
        host(
          NearbyAirportsSection(latitude: 1, longitude: 2, createBloc: factory),
        ),
      );
      await tester.pumpWidget(const SizedBox());

      verify(() => own.close()).called(1);
    });

    testWidgets('ignores its factory when NearbyBlocs is provided', (
      tester,
    ) async {
      final provided = MockAirportBloc();
      when(() => provided.state).thenReturn(AirportInitial());

      await tester.pumpWidget(
        host(
          NearbyAirportsSection(latitude: 1, longitude: 2, createBloc: factory),
          nearby: NearbyBlocs(airports: provided, stations: MockStationBloc()),
        ),
      );

      expect(created, 0);
      verifyNever(() => provided.add(any()));
    });
  });
}
