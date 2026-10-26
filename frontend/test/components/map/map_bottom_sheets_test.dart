import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/components/map/map_bottom_sheets.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/station.dart';

class MockTripBloc extends Mock implements TripBloc {}

void main() {
  late TripBloc tripBloc;

  setUpAll(() {
    registerFallbackValue(const ClearTrip());
  });

  setUp(() {
    tripBloc = MockTripBloc();
    when(() => tripBloc.state).thenReturn(const TripState());
    when(() => tripBloc.stream).thenAnswer((_) => Stream<TripState>.empty());
    when(() => tripBloc.close()).thenAnswer((_) => Future.value());
  });

  group('AirportBottomSheet', () {
    final airport = Airport(
      name: 'San Francisco International Airport',
      iataCode: 'SFO',
      city: 'San Francisco',
      country: 'USA',
      latitude: 37.6213,
      longitude: -122.3790,
      airportType: 'large_airport',
    );

    testWidgets('renders airport information correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: tripBloc,
              child: AirportBottomSheet(airport: airport),
            ),
          ),
        ),
      );

      expect(find.text('San Francisco International Airport'), findsOneWidget);
      expect(find.text('SFO'), findsOneWidget);
      expect(find.text('San Francisco, USA'), findsOneWidget);
      expect(find.text('International Airport'), findsOneWidget);
    });

    testWidgets('Add to Trip button dispatches AddAirportStop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: tripBloc,
              child: AirportBottomSheet(airport: airport),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Add to Trip'));
      verify(() => tripBloc.add(any(that: isA<AddAirportStop>()))).called(1);
    });
  });

  group('StationBottomSheet', () {
    final station = Station(
      name: 'Grand Central Terminal',
      osmId: 123,
      city: 'New York',
      country: 'USA',
      latitude: 40.7527,
      longitude: -73.9772,
      stationType: 'major_station',
      uicRef: '8000001',
    );

    testWidgets('renders station information correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: tripBloc,
              child: StationBottomSheet(station: station),
            ),
          ),
        ),
      );

      expect(find.text('Grand Central Terminal'), findsOneWidget);
      expect(find.text('Ref: 8000001'), findsOneWidget);
      expect(find.text('New York, USA'), findsOneWidget);
      expect(find.text('Major Station'), findsOneWidget);
    });

    testWidgets('Add to Trip button dispatches AddStationStop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: tripBloc,
              child: StationBottomSheet(station: station),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Add to Trip'));
      verify(() => tripBloc.add(any(that: isA<AddStationStop>()))).called(1);
    });
  });

  group('sheet details', () {
    Future<void> pumpSheet(WidgetTester tester, Widget sheet) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(value: tripBloc, child: sheet),
            ),
          ),
        );

    testWidgets('a non-large airport reads as regional', (tester) async {
      await pumpSheet(
        tester,
        AirportBottomSheet(
          airport: Airport(
            name: 'Hayward Executive',
            iataCode: 'HWD',
            city: 'Hayward',
            country: 'USA',
            latitude: 37.6,
            longitude: -122.1,
            airportType: 'small_airport',
          ),
        ),
      );

      expect(find.text('Regional Airport'), findsOneWidget);
      expect(find.byIcon(Icons.flight), findsOneWidget);
    });

    for (final (type, label, icon) in [
      ('commuter_rail_station', 'Commuter Rail', Icons.directions_railway),
      ('subway_station', 'Subway Station', Icons.subway),
      ('regional_station', 'Regional Station', Icons.train),
      ('halt', 'halt', Icons.train),
      (null, 'Station', Icons.train),
    ]) {
      testWidgets('labels a ${type ?? 'typeless'} station "$label"', (
        tester,
      ) async {
        await pumpSheet(
          tester,
          StationBottomSheet(
            station: Station(
              name: 'Somewhere',
              osmId: 1,
              latitude: 0,
              longitude: 0,
              stationType: type,
            ),
          ),
        );

        expect(find.text(label), findsOneWidget);
        expect(find.byIcon(icon), findsOneWidget);
      });
    }

    testWidgets('a station without a reference or place still reads', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        StationBottomSheet(
          station: Station(
            name: 'Somewhere',
            osmId: 1,
            latitude: 0,
            longitude: 0,
            uicRef: '',
          ),
        ),
      );

      expect(find.textContaining('Ref:'), findsNothing);
      expect(find.text('Unknown City, Unknown Country'), findsOneWidget);
    });

    testWidgets('a base sheet without an action has no Add to Trip', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        const BaseBottomSheet(
          icon: Icons.place,
          color: Colors.red,
          title: 'Pinned place',
          location: 'Here',
          label: 'Note',
        ),
      );

      expect(find.text('Pinned place'), findsOneWidget);
      expect(find.text('Add to Trip'), findsNothing);
    });
  });

  group('adding from a presented sheet', () {
    Future<void> present(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        BlocProvider.value(
          value: tripBloc,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => sheet,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('airport: adds, closes the sheet and confirms', (tester) async {
      final airport = Airport(
        name: 'Oakland International',
        iataCode: 'OAK',
        city: 'Oakland',
        country: 'USA',
        latitude: 37.7,
        longitude: -122.2,
        airportType: 'large_airport',
      );
      await present(tester, AirportBottomSheet(airport: airport));

      await tester.tap(find.text('Add to Trip'));
      await tester.pumpAndSettle();

      verify(() => tripBloc.add(AddAirportStop(airport))).called(1);
      expect(find.byType(AirportBottomSheet), findsNothing);
      expect(find.text('Added Oakland International to trip'), findsOneWidget);
    });

    testWidgets('station: adds, closes the sheet and confirms', (tester) async {
      final station = Station(
        name: 'Union Station',
        osmId: 9,
        latitude: 41.8,
        longitude: -87.6,
      );
      await present(tester, StationBottomSheet(station: station));

      await tester.tap(find.text('Add to Trip'));
      await tester.pumpAndSettle();

      verify(() => tripBloc.add(AddStationStop(station))).called(1);
      expect(find.byType(StationBottomSheet), findsNothing);
      expect(find.text('Added Union Station to trip'), findsOneWidget);
    });
  });
}
