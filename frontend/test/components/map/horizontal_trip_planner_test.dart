import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/components/map/horizontal_trip_planner.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/models/trip.dart';

class MockTripBloc extends Bloc<TripEvent, TripState> implements TripBloc {
  MockTripBloc(super.initialState);

  final List<TripEvent> events = [];

  @override
  void add(TripEvent event) {
    events.add(event);
  }
}

void main() {
  final person = Person(
    id: '1',
    firstName: 'Alice',
    lastName: 'Smith',
    relationshipTag: 'Friend',
    city: 'NY',
    state: 'NY',
    country: 'USA',
  );

  final stops = [
    TripStop(location: const LatLng(0, 0), sequenceOrder: 0, people: [person]),
    const TripStop(location: LatLng(1, 1), sequenceOrder: 1),
  ];

  testWidgets('HorizontalTripPlanner renders stops correctly', (tester) async {
    final tripBloc = MockTripBloc(TripState(stops: stops));

    await tester.pumpWidget(
      MaterialApp(
        // HorizontalTripPlanner is map chrome: in production it renders inside
        // MapScreen's BackdropGroup, which is what lets its glass share a single
        // backdrop sample. The fragment test has to supply that ancestor, the
        // same way a fragment using Ink has to supply a Material.
        home: BackdropGroup(
          child: Scaffold(
            body: Stack(
              children: [
                BlocProvider<TripBloc>.value(
                  value: tripBloc,
                  child: const HorizontalTripPlanner(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Verify stops are rendered
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('HorizontalTripPlanner Clear button dispatches ClearTrip', (
    tester,
  ) async {
    final tripBloc = MockTripBloc(TripState(stops: stops));

    await tester.pumpWidget(
      MaterialApp(
        // HorizontalTripPlanner is map chrome: in production it renders inside
        // MapScreen's BackdropGroup, which is what lets its glass share a single
        // backdrop sample. The fragment test has to supply that ancestor, the
        // same way a fragment using Ink has to supply a Material.
        home: BackdropGroup(
          child: Scaffold(
            body: Stack(
              children: [
                BlocProvider<TripBloc>.value(
                  value: tripBloc,
                  child: const HorizontalTripPlanner(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.layers_clear));
    await tester.pump();

    expect(tripBloc.events.any((e) => e is ClearTrip), isTrue);
  });

  testWidgets('HorizontalTripPlanner Save button dispatches SaveTrip', (
    tester,
  ) async {
    final tripBloc = MockTripBloc(TripState(stops: stops));

    await tester.pumpWidget(
      MaterialApp(
        // HorizontalTripPlanner is map chrome: in production it renders inside
        // MapScreen's BackdropGroup, which is what lets its glass share a single
        // backdrop sample. The fragment test has to supply that ancestor, the
        // same way a fragment using Ink has to supply a Material.
        home: BackdropGroup(
          child: Scaffold(
            body: Stack(
              children: [
                BlocProvider<TripBloc>.value(
                  value: tripBloc,
                  child: const HorizontalTripPlanner(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pump();

    expect(tripBloc.events.any((e) => e is SaveTrip), isTrue);
    final saveEvent =
        tripBloc.events.firstWhere((e) => e is SaveTrip) as SaveTrip;
    expect(saveEvent.status, TripStatus.draft);
    expect(saveEvent.name, startsWith('Draft Trip'));
  });

  group('stop chips', () {
    Person friend(String first) => Person(
      id: first,
      firstName: first,
      lastName: 'X',
      relationshipTag: 'Friend',
      city: 'NY',
      state: 'NY',
      country: 'USA',
    );

    final sfo = Airport(
      name: 'San Francisco International',
      iataCode: 'SFO',
      airportType: 'large_airport',
      city: 'San Francisco',
      country: 'USA',
      latitude: 37.6,
      longitude: -122.4,
    );

    final union = Station(
      name: 'Union Station',
      osmId: 1,
      latitude: 41.8,
      longitude: -87.6,
    );

    Future<void> pumpPlanner(
      WidgetTester tester,
      List<TripStop> stops, {
      Size size = const Size(400, 800),
      double bottomPadding = 0,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: EdgeInsets.only(bottom: bottomPadding),
            ),
            child: BackdropGroup(
              child: Scaffold(
                body: Stack(
                  children: [
                    BlocProvider<TripBloc>.value(
                      value: MockTripBloc(TripState(stops: stops)),
                      child: const HorizontalTripPlanner(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders nothing without stops', (tester) async {
      await pumpPlanner(tester, const []);

      expect(find.byType(Positioned), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('names a shared person stop by its first person, +N', (
      tester,
    ) async {
      await pumpPlanner(tester, [
        TripStop(
          location: const LatLng(0, 0),
          sequenceOrder: 0,
          people: [friend('Alice'), friend('Bob'), friend('Cy')],
        ),
      ]);

      expect(find.text('Alice +2'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      // A person-only stop shows no headcount badge or avatar strip.
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('an airport stop shows its code, icon and travellers', (
      tester,
    ) async {
      await pumpPlanner(tester, [
        TripStop(
          location: const LatLng(0, 0),
          sequenceOrder: 0,
          airport: sfo,
          people: [friend('Alice'), friend('Bob'), friend('Cy'), friend('Dee')],
        ),
      ]);

      expect(find.text('SFO'), findsOneWidget);
      expect(find.byIcon(Icons.flight), findsOneWidget);
      // The icon replaces the stop letter.
      expect(find.text('A'), findsOneWidget); // Alice's avatar initial
      expect(find.text('4'), findsOneWidget); // headcount badge
      // Avatars are capped at three.
      expect(find.byType(CircleAvatar), findsNWidgets(3));
      expect(find.text('D'), findsNothing);
    });

    testWidgets('a station stop shows its name and a train', (tester) async {
      await pumpPlanner(tester, [
        TripStop(
          location: const LatLng(0, 0),
          sequenceOrder: 0,
          station: union,
        ),
        const TripStop(location: LatLng(1, 1), sequenceOrder: 1),
      ]);

      expect(find.text('Union Station'), findsOneWidget);
      expect(find.byIcon(Icons.train), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      // No travellers, no badge.
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('sits above the bottom bar and the safe area', (tester) async {
      await pumpPlanner(tester, [
        const TripStop(location: LatLng(0, 0), sequenceOrder: 0),
      ], bottomPadding: 20);

      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.bottom, 24 + 88 + 20);
      expect(positioned.left, 16);
      expect(positioned.right, 16);
    });

    testWidgets('beside a rail it drops the bar and safe-area insets', (
      tester,
    ) async {
      await pumpPlanner(
        tester,
        [const TripStop(location: LatLng(0, 0), sequenceOrder: 0)],
        size: const Size(1200, 900),
        bottomPadding: 20,
      );

      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.bottom, 24);
      expect(positioned.left, 24);
    });

    testWidgets('labels its actions for assistive technology', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPlanner(tester, [
        const TripStop(location: LatLng(0, 0), sequenceOrder: 0),
      ]);

      expect(find.bySemanticsLabel('Save Trip'), findsOneWidget);
      expect(find.bySemanticsLabel('Clear Trip'), findsOneWidget);
      semantics.dispose();
    });
  });
}
