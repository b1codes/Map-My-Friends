import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/screens/trips/trip_details_screen.dart';
import 'package:map_my_friends/services/routing_service.dart';

class MockMapSettingsCubit extends Mock implements MapSettingsCubit {}

class MockRoutingService extends Mock implements RoutingService {}

TripStop _stop(
  String id,
  int order,
  LatLng at, {
  Map<String, dynamic>? metadata,
  String? address,
  List<Person> people = const [],
  Airport? airport,
  Station? station,
}) => TripStop(
  id: id,
  location: at,
  sequenceOrder: order,
  snapshotMetadata: metadata,
  snapshotAddress: address,
  people: people,
  airport: airport,
  station: station,
);

const _berlin = LatLng(52.52, 13.405);
const _paris = LatLng(48.8566, 2.3522);
const _rome = LatLng(41.9, 12.5);

void main() {
  testWidgets('TripDetailsScreen builds successfully', (
    WidgetTester tester,
  ) async {
    final mapSettingsCubit = MockMapSettingsCubit();
    when(() => mapSettingsCubit.state).thenReturn(const MapSettingsState());
    when(
      () => mapSettingsCubit.stream,
    ).thenAnswer((_) => Stream<MapSettingsState>.empty());
    when(() => mapSettingsCubit.close()).thenAnswer((_) => Future.value());

    final trip = Trip(
      id: '1',
      name: 'Test Trip',
      date: DateTime.now(),
      status: TripStatus.booked,
      stops: [
        TripStop(
          id: '1',
          location: const LatLng(52.5200, 13.4050),
          sequenceOrder: 0,
          snapshotAddress: 'Berlin, Germany',
          snapshotMetadata: {'people': 'John Doe'},
        ),
        TripStop(
          id: '2',
          location: const LatLng(48.8566, 2.3522),
          sequenceOrder: 1,
          snapshotAddress: 'Paris, France',
          snapshotMetadata: {'people': 'Jane Smith'},
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<MapSettingsCubit>.value(
          value: mapSettingsCubit,
          child: TripDetailsScreen(trip: trip),
        ),
      ),
    );

    expect(find.text('Test Trip'), findsOneWidget);
    expect(find.text('BOOKED'), findsOneWidget);
    expect(find.text('John Doe'), findsOneWidget);
    expect(find.text('Berlin, Germany'), findsOneWidget);
    expect(find.text('Jane Smith'), findsOneWidget);
    expect(find.text('Paris, France'), findsOneWidget);
  });

  group('with an injected router', () {
    late MockMapSettingsCubit settings;
    late MockRoutingService routing;

    setUpAll(() {
      registerFallbackValue(<TripStop>[]);
    });

    setUp(() {
      settings = MockMapSettingsCubit();
      routing = MockRoutingService();
      when(() => settings.state).thenReturn(const MapSettingsState());
      when(
        () => settings.stream,
      ).thenAnswer((_) => const Stream<MapSettingsState>.empty());
      when(() => settings.close()).thenAnswer((_) async {});
      when(() => routing.getRoute(any())).thenAnswer((_) async => []);
    });

    final twoStops = Trip(
      id: 't1',
      name: 'Euro Tour',
      date: DateTime(2026, 3, 5),
      status: TripStatus.draft,
      stops: [
        _stop('s1', 0, _berlin, metadata: {'people': 'Ann'}),
        _stop('s2', 1, _paris, metadata: {'people': 'Bob'}),
      ],
    );

    Future<void> pumpDetails(
      WidgetTester tester,
      Trip trip, {
      Size size = const Size(400, 900),
      Locale? locale,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        BlocProvider<MapSettingsCubit>.value(
          value: settings,
          child: MaterialApp(
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: [locale ?? const Locale('en')],
            locale: locale,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TripDetailsScreen(
                          trip: trip,
                          routingService: routing,
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
    }

    String tileUrl(WidgetTester tester) =>
        tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate!;

    group('route', () {
      testWidgets('asks the router for the trip stops and draws its line', (
        tester,
      ) async {
        when(
          () => routing.getRoute(any()),
        ).thenAnswer((_) async => const [_berlin, LatLng(50, 8), _paris]);
        await pumpDetails(tester, twoStops);

        verify(() => routing.getRoute(twoStops.stops)).called(1);
        final line = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
        expect(line.polylines.single.points, const [
          _berlin,
          LatLng(50, 8),
          _paris,
        ]);
      });

      testWidgets('draws no line until the route arrives', (tester) async {
        final route = Completer<List<LatLng>>();
        when(() => routing.getRoute(any())).thenAnswer((_) => route.future);
        await pumpDetails(tester, twoStops);

        expect(find.byType(PolylineLayer), findsNothing);
        // Stops are on the map regardless.
        expect(
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
          hasLength(2),
        );

        route.complete(const [_berlin, _paris]);
        await tester.pump();

        expect(find.byType(PolylineLayer), findsOneWidget);
      });

      testWidgets('a routing failure leaves the map without a line', (
        tester,
      ) async {
        when(
          () => routing.getRoute(any()),
        ).thenAnswer((_) async => throw Exception('OSRM down'));
        await pumpDetails(tester, twoStops);

        expect(find.byType(PolylineLayer), findsNothing);
        expect(find.text('Euro Tour'), findsOneWidget);
        expect(
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
          hasLength(2),
        );
      });

      testWidgets('letters each stop marker in order', (tester) async {
        final three = twoStops.copyWith(
          stops: [...twoStops.stops, _stop('s3', 2, _rome)],
        );
        await pumpDetails(tester, three, size: const Size(1400, 900));

        final markers = tester
            .widget<MarkerLayer>(find.byType(MarkerLayer))
            .markers;
        expect(markers.map((m) => m.point), [_berlin, _paris, _rome]);
        for (final (i, letter) in ['A', 'B', 'C'].indexed) {
          expect(
            find.descendant(
              of: find.byWidget(markers[i].child),
              matching: find.text(letter),
            ),
            findsOneWidget,
          );
        }
      });

      testWidgets('fits the camera to all stops', (tester) async {
        await pumpDetails(tester, twoStops, size: const Size(1400, 900));

        final options = tester.widget<FlutterMap>(find.byType(FlutterMap));
        final fit = options.options.initialCameraFit! as FitBounds;
        expect(fit.bounds.contains(_berlin), isTrue);
        expect(fit.bounds.contains(_paris), isTrue);
        // The background map is a picture, not something to pan.
        expect(options.options.interactionOptions.flags, InteractiveFlag.none);
      });

      testWidgets('centres on a lone stop', (tester) async {
        await pumpDetails(
          tester,
          twoStops.copyWith(stops: [twoStops.stops.first]),
        );
        final options = tester.widget<FlutterMap>(find.byType(FlutterMap));
        expect(options.options.initialCameraFit, isNull);
        expect(options.options.initialCenter, _berlin);
      });

      testWidgets('centres on the origin for a trip with no stops', (
        tester,
      ) async {
        await pumpDetails(tester, twoStops.copyWith(stops: []));

        final options = tester.widget<FlutterMap>(find.byType(FlutterMap));
        expect(options.options.initialCameraFit, isNull);
        expect(options.options.initialCenter, const LatLng(0, 0));
        expect(
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
          isEmpty,
        );
      });
    });

    group('header and timeline', () {
      for (final c in <(TripStatus, String)>[
        (TripStatus.draft, 'DRAFT'),
        (TripStatus.booked, 'BOOKED'),
        (TripStatus.cancelled, 'CANCELLED'),
      ]) {
        testWidgets('shows the ${c.$2} badge and the formatted date', (
          tester,
        ) async {
          await pumpDetails(tester, twoStops.copyWith(status: c.$1));

          expect(find.text(c.$2), findsOneWidget);
          expect(find.text('March 5, 2026'), findsOneWidget);
        });
      }

      testWidgets('names each stop from whatever it carries', (tester) async {
        final ann = Person(
          id: 'p1',
          firstName: 'Ann',
          lastName: 'Lee',
          relationshipTag: 'FRIEND',
          city: 'Berlin',
          state: '',
          country: 'DE',
        );
        final trip = twoStops.copyWith(
          stops: [
            _stop(
              'a',
              0,
              _berlin,
              metadata: {
                'people': [
                  {'name': 'Ann Lee'},
                  'Bob Ray',
                ],
              },
              address: 'Unter den Linden',
            ),
            _stop(
              'b',
              1,
              _paris,
              metadata: {
                'hub': {'name': 'Gare du Nord'},
              },
            ),
            _stop('c', 2, _rome, people: [ann]),
            _stop(
              'd',
              3,
              _rome,
              airport: Airport(
                name: 'Fiumicino',
                iataCode: 'FCO',
                airportType: 'large_airport',
                city: 'Rome',
                country: 'IT',
                latitude: 41.8,
                longitude: 12.25,
              ),
            ),
            _stop(
              'e',
              4,
              _rome,
              station: Station(
                name: 'Roma Termini',
                osmId: 1,
                latitude: 41.9,
                longitude: 12.5,
              ),
            ),
          ],
        );
        await pumpDetails(tester, trip, size: const Size(1400, 2000));

        expect(find.text('Ann Lee, Bob Ray'), findsOneWidget);
        expect(find.text('Unter den Linden'), findsOneWidget);
        expect(find.text('Gare du Nord'), findsOneWidget);
        expect(find.text('Ann Lee'), findsOneWidget);
        expect(find.text('Fiumicino'), findsOneWidget);
        expect(find.text('Roma Termini'), findsOneWidget);
      });

      testWidgets('shows each leg with its transport and booking reference, '
          'and a car between stops with no leg', (tester) async {
        final trip = twoStops.copyWith(
          stops: [
            ...twoStops.stops,
            _stop('s3', 2, _rome),
            _stop('s4', 3, _rome),
            _stop('s5', 4, _rome),
          ],
          legs: const [
            TripLeg(
              departureStopId: 's1',
              arrivalStopId: 's2',
              transportType: 'FLIGHT',
              bookingReference: 'LH123',
            ),
            TripLeg(
              departureStopId: 's2',
              arrivalStopId: 's3',
              transportType: 'TRAIN',
            ),
            TripLeg(
              departureStopId: 's3',
              arrivalStopId: 's4',
              transportType: 'BUS',
            ),
          ],
        );
        await pumpDetails(tester, trip, size: const Size(1400, 2000));

        expect(find.byIcon(Icons.flight_takeoff), findsOneWidget);
        expect(find.text('Ref: LH123'), findsOneWidget);
        expect(find.byIcon(Icons.train), findsOneWidget);
        expect(find.byIcon(Icons.directions_bus), findsOneWidget);
        // s4 -> s5 has no leg yet; the last stop starts none.
        expect(find.byIcon(Icons.directions_car), findsOneWidget);
        expect(find.textContaining('Ref:'), findsOneWidget);
      });

      testWidgets('lays out side by side on a wide window', (tester) async {
        await pumpDetails(tester, twoStops, size: const Size(1400, 900));

        expect(
          tester.getSize(find.text('Euro Tour')).width,
          lessThan(380),
          reason: 'the header sits in the 380px side panel',
        );
        expect(tester.getTopLeft(find.byType(FlutterMap)).dx, 380);
      });

      testWidgets('overlays the timeline on the map on a phone', (
        tester,
      ) async {
        await pumpDetails(tester, twoStops);

        expect(tester.getTopLeft(find.byType(FlutterMap)).dx, 0);
        expect(tester.getSize(find.byType(FlutterMap)).width, 400);
      });

      testWidgets('Back returns to the previous screen', (tester) async {
        await pumpDetails(tester, twoStops);

        await tester.tap(find.byTooltip('Back'));
        await _settle(tester);

        expect(find.byType(TripDetailsScreen), findsNothing);
        expect(find.text('open'), findsOneWidget);
      });
    });

    group('leg details', () {
      final trip = twoStops.copyWith(
        legs: [
          TripLeg(
            departureStopId: 's1',
            arrivalStopId: 's2',
            transportType: 'TRAIN',
            bookingReference: 'DB42',
            departureTime: DateTime(2026, 3, 5, 9, 30),
            arrivalTime: DateTime(2026, 3, 5, 17, 5),
          ),
        ],
      );

      Future<void> openLeg(WidgetTester tester, Trip trip) async {
        await pumpDetails(tester, trip, size: const Size(1400, 900));
        await tester.tap(find.byIcon(Icons.train));
        await _settle(tester);
      }

      testWidgets('tapping a leg shows its details', (tester) async {
        await openLeg(tester, trip);

        expect(find.text('Leg Details'), findsOneWidget);
        expect(find.text('TRAIN'), findsOneWidget);
        expect(find.text('DB42'), findsOneWidget);
        expect(find.text('09:30, Mar 5'), findsOneWidget);
        expect(find.text('17:05, Mar 5'), findsOneWidget);
      });

      testWidgets('a leg without a booking says so and omits times', (
        tester,
      ) async {
        await pumpDetails(tester, twoStops, size: const Size(1400, 900));
        await tester.tap(find.byIcon(Icons.directions_car));
        await _settle(tester);

        expect(find.text('CAR'), findsOneWidget);
        expect(find.text('Not set'), findsOneWidget);
        expect(find.text('Departure'), findsNothing);
        expect(find.text('Arrival'), findsNothing);
      });

      testWidgets('the close button dismisses the sheet', (tester) async {
        await openLeg(tester, trip);

        await tester.tap(find.byIcon(Icons.close));
        await _settle(tester);

        expect(find.text('Leg Details'), findsNothing);
        expect(find.byType(TripDetailsScreen), findsOneWidget);
      });

      testWidgets('Edit Details closes the sheet and says editing is coming', (
        tester,
      ) async {
        await openLeg(tester, trip);

        await tester.tap(find.text('Edit Details'));
        await _settle(tester);

        expect(find.text('Leg Details'), findsNothing);
        expect(
          find.text('Editing will be implemented in the next iteration.'),
          findsOneWidget,
        );
      });
    });

    group('tiles', () {
      for (final c in <(MapSettingsState, String)>[
        (
          const MapSettingsState(),
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        ),
        (
          const MapSettingsState(mapType: MapType.satellite),
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        ),
        (
          const MapSettingsState(mapType: MapType.minimal),
          'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
        ),
        (
          const MapSettingsState(
            mapType: MapType.minimal,
            themeMode: ThemeMode.dark,
          ),
          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
        ),
        (
          const MapSettingsState(themeMode: ThemeMode.dark),
          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
        ),
      ]) {
        testWidgets('uses ${c.$2} for ${c.$1.mapType.name}/'
            '${c.$1.themeMode.name}', (tester) async {
          when(() => settings.state).thenReturn(c.$1);
          await pumpDetails(tester, twoStops);

          expect(tileUrl(tester), c.$2);
        });
      }

      for (final c in <(Locale, String)>[
        (
          const Locale('de'),
          'https://{s}.tile.openstreetmap.de/tiles/osmde/{z}/{x}/{y}.png',
        ),
        (
          const Locale('fr'),
          'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
        ),
      ]) {
        testWidgets('uses the ${c.$1.languageCode} OSM mirror in that '
            'locale', (tester) async {
          await pumpDetails(tester, twoStops, locale: c.$1);

          expect(tileUrl(tester), c.$2);
        });
      }
    });
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}
