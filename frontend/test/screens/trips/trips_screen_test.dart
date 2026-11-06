import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/screens/trips/trip_details_screen.dart';
import 'package:map_my_friends/screens/trips/trips_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockTripBloc extends MockBloc<TripEvent, TripState> implements TripBloc {}

class MockMapSettingsCubit extends MockCubit<MapSettingsState>
    implements MapSettingsCubit {}

/// Stops without people, so opening a booked trip routes with straight lines
/// and never reaches the network.
List<TripStop> _stops(int n) => [
  for (var i = 0; i < n; i++)
    TripStop(
      id: 's$i',
      location: LatLng(40.0 + i, -74.0 - i),
      sequenceOrder: i,
      snapshotMetadata: {'people': 'Stop $i'},
    ),
];

final _booked = Trip(
  id: 'b1',
  name: 'Lisbon Weekend',
  date: DateTime(2026, 3, 5),
  startDate: DateTime(2026, 3, 5),
  endDate: DateTime(2026, 3, 9),
  status: TripStatus.booked,
  stops: _stops(2),
);

final _draft = Trip(
  id: 'd1',
  name: 'Road Trip Idea',
  date: DateTime(2026, 6, 1),
  status: TripStatus.draft,
  stops: _stops(3),
);

final _sameDay = Trip(
  id: 'd2',
  name: 'Day Out',
  date: DateTime(2026, 1, 1),
  startDate: DateTime(2026, 7, 4),
  endDate: DateTime(2026, 7, 4),
  status: TripStatus.draft,
);

final _cancelled = Trip(
  id: 'c1',
  name: 'Called Off',
  date: DateTime(2026, 2, 14),
  status: TripStatus.cancelled,
  stops: _stops(1),
);

void main() {
  late MockTripBloc tripBloc;
  late MockMapSettingsCubit settings;
  late int mapRequests;

  setUpAll(() {
    registerFallbackValue(const ClearTrip());
  });

  setUp(() {
    tripBloc = MockTripBloc();
    settings = MockMapSettingsCubit();
    mapRequests = 0;
    when(() => tripBloc.state).thenReturn(const TripState());
    when(() => settings.state).thenReturn(const MapSettingsState());
  });

  Future<void> pumpTrips(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TripBloc>.value(value: tripBloc),
          BlocProvider<MapSettingsCubit>.value(value: settings),
        ],
        child: MaterialApp(
          // The shell provides the backdrop group in the app.
          home: BackdropGroup(
            child: TripsScreen(onNavigateToMap: () => mapRequests++),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void withTrips(List<Trip> trips, {String? currentTripId}) {
    when(
      () => tripBloc.state,
    ).thenReturn(TripState(userTrips: trips, currentTripId: currentTripId));
  }

  Future<void> openMenu(WidgetTester tester, String tripName) async {
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, tripName),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await _settle(tester);
  }

  testWidgets('shows a loading indicator while the first load runs', (
    tester,
  ) async {
    when(() => tripBloc.state).thenReturn(const TripState(isLoading: true));
    await pumpTrips(tester);

    expect(find.byType(PulseIndicator), findsOneWidget);
    expect(find.text('No Trips Yet'), findsNothing);
  });

  testWidgets('keeps showing the list while a refresh runs', (tester) async {
    when(
      () => tripBloc.state,
    ).thenReturn(TripState(userTrips: [_draft], isLoading: true));
    await pumpTrips(tester);

    expect(find.byType(PulseIndicator), findsNothing);
    expect(find.text('Road Trip Idea'), findsOneWidget);
  });

  testWidgets('with no trips, offers to start planning on the map', (
    tester,
  ) async {
    await pumpTrips(tester);

    expect(find.text('My Trips'), findsOneWidget);
    expect(find.text('No Trips Yet'), findsOneWidget);
    expect(find.text('Plan your first route on the map!'), findsOneWidget);

    await tester.tap(find.text('Start Planning'));
    await tester.pump();

    expect(mapRequests, 1);
  });

  testWidgets('groups trips by status: booked, then drafts, then cancelled', (
    tester,
  ) async {
    withTrips([_cancelled, _draft, _booked, _sameDay]);
    await pumpTrips(tester);

    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Booked'), lessThan(y('Lisbon Weekend')));
    expect(y('Lisbon Weekend'), lessThan(y('Drafts')));
    expect(y('Drafts'), lessThan(y('Road Trip Idea')));
    expect(y('Road Trip Idea'), lessThan(y('Day Out')));
    expect(y('Day Out'), lessThan(y('Cancelled')));
    expect(y('Cancelled'), lessThan(y('Called Off')));

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.edit_note), findsNWidgets(2));
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
  });

  testWidgets('omits the headers of empty groups', (tester) async {
    withTrips([_draft]);
    await pumpTrips(tester);

    expect(find.text('Drafts'), findsOneWidget);
    expect(find.text('Booked'), findsNothing);
    expect(find.text('Cancelled'), findsNothing);
  });

  testWidgets('summarises dates and stop counts', (tester) async {
    withTrips([_booked, _draft, _sameDay]);
    await pumpTrips(tester);

    // A range when the trip spans days.
    expect(find.text('Mar 5 - Mar 9 • 2 stops'), findsOneWidget);
    // The planned date when there is no start date.
    expect(find.text('Jun 1 • 3 stops'), findsOneWidget);
    // One date when it starts and ends the same day.
    expect(find.text('Jul 4 • 0 stops'), findsOneWidget);
  });

  testWidgets('emphasises the trip currently loaded on the map', (
    tester,
  ) async {
    withTrips([_draft, _sameDay], currentTripId: 'd2');
    await pumpTrips(tester);

    FontWeight? weight(String name) =>
        tester.widget<Text>(find.text(name)).style?.fontWeight;
    expect(weight('Day Out'), FontWeight.bold);
    expect(weight('Road Trip Idea'), FontWeight.normal);
  });

  testWidgets('tapping a booked trip opens its itinerary', (tester) async {
    withTrips([_booked]);
    await pumpTrips(tester);

    await tester.tap(find.text('Lisbon Weekend'));
    await _settle(tester);

    final details = tester.widget<TripDetailsScreen>(
      find.byType(TripDetailsScreen),
    );
    expect(details.trip, same(_booked));
    verifyNever(() => tripBloc.add(any()));
    expect(mapRequests, 0);
  });

  testWidgets('tapping a draft loads it into the planner on the map', (
    tester,
  ) async {
    withTrips([_draft]);
    await pumpTrips(tester);

    await tester.tap(find.text('Road Trip Idea'));
    await tester.pump();

    verify(() => tripBloc.add(LoadTrip(_draft))).called(1);
    expect(mapRequests, 1);
    expect(find.byType(TripDetailsScreen), findsNothing);
  });

  testWidgets('"View on Map" loads any trip, booked ones included', (
    tester,
  ) async {
    withTrips([_booked]);
    await pumpTrips(tester);

    await openMenu(tester, 'Lisbon Weekend');
    expect(find.text('Update Status'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('View on Map'));
    await _settle(tester);

    verify(() => tripBloc.add(LoadTrip(_booked))).called(1);
    expect(mapRequests, 1);
  });

  testWidgets('"Update Status" lists every status and marks the current one', (
    tester,
  ) async {
    withTrips([_draft]);
    await pumpTrips(tester);

    await openMenu(tester, 'Road Trip Idea');
    await tester.tap(find.text('Update Status'));
    await _settle(tester);

    expect(find.text('Update Trip Status'), findsOneWidget);
    for (final label in ['DRAFT', 'BOOKED', 'CANCELLED']) {
      expect(find.text(label), findsOneWidget);
    }
    // Only the trip's own status carries the check.
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('DRAFT'), matching: find.byType(Row)),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('Close'));
    await _settle(tester);

    expect(find.text('Update Trip Status'), findsNothing);
    verifyNever(() => tripBloc.add(any()));
  });

  testWidgets('choosing a status updates that trip and closes the dialog', (
    tester,
  ) async {
    withTrips([_draft]);
    await pumpTrips(tester);

    await openMenu(tester, 'Road Trip Idea');
    await tester.tap(find.text('Update Status'));
    await _settle(tester);
    await tester.tap(find.text('BOOKED'));
    await _settle(tester);

    // The trip chosen in the list, not whatever the planner has open.
    verify(
      () => tripBloc.add(UpdateTripStatus(_draft, TripStatus.booked)),
    ).called(1);
    expect(find.text('Update Trip Status'), findsNothing);
  });

  testWidgets('deleting asks first, and cancelling keeps the trip', (
    tester,
  ) async {
    withTrips([_draft]);
    await pumpTrips(tester);

    await openMenu(tester, 'Road Trip Idea');
    await tester.tap(find.text('Delete'));
    await _settle(tester);

    expect(find.text('Delete Trip'), findsOneWidget);
    expect(
      find.text(
        'This removes "Road Trip Idea" and its itinerary. It cannot be undone.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await _settle(tester);

    verifyNever(() => tripBloc.add(any()));
  });

  testWidgets('confirming the delete removes that trip', (tester) async {
    withTrips([_draft, _cancelled]);
    await pumpTrips(tester);

    await openMenu(tester, 'Called Off');
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Delete')),
    );
    await _settle(tester);

    verify(() => tripBloc.add(const DeleteTrip('c1'))).called(1);
    expect(find.text('Delete Trip'), findsNothing);
  });

  testWidgets('rebuilds when trips arrive', (tester) async {
    whenListen(
      tripBloc,
      Stream<TripState>.value(TripState(userTrips: [_booked])),
      initialState: const TripState(isLoading: true),
    );
    await pumpTrips(tester);
    await tester.pump();

    expect(find.byType(PulseIndicator), findsNothing);
    expect(find.text('Lisbon Weekend'), findsOneWidget);
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}
