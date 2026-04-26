import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/components/map/horizontal_trip_planner.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/trip.dart';

class MockTripBloc extends Bloc<TripEvent, TripState> implements TripBloc {
  MockTripBloc(TripState initialState) : super(initialState);

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
        home: Scaffold(
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
        home: Scaffold(
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
        home: Scaffold(
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
    );

    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pump();

    expect(tripBloc.events.any((e) => e is SaveTrip), isTrue);
    final saveEvent =
        tripBloc.events.firstWhere((e) => e is SaveTrip) as SaveTrip;
    expect(saveEvent.status, TripStatus.draft);
    expect(saveEvent.name, startsWith('Draft Trip'));
  });
}
