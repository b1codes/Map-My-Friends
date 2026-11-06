import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/components/map/map_bottom_sheets.dart';
import 'package:map_my_friends/components/map/unified_cluster_modal.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/screens/people/person_details_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockTripBloc extends MockBloc<TripEvent, TripState> implements TripBloc {}

class MockPeopleBloc extends MockBloc<PeopleEvent, PeopleState>
    implements PeopleBloc {}

final _ada = Person(
  id: 'p1',
  firstName: 'Ada',
  lastName: 'Lovelace',
  relationshipTag: 'FRIEND',
  city: 'London',
  state: 'England',
  country: 'UK',
);

final _sfo = Airport(
  id: 42,
  name: 'San Francisco International',
  iataCode: 'SFO',
  airportType: 'large_airport',
  city: 'San Francisco',
  country: 'USA',
  latitude: 37.6,
  longitude: -122.4,
);

Station _station({
  String name = 'Union Station',
  String? type = 'major_station',
  String? city = 'Chicago',
  int? id = 7,
}) => Station(
  id: id,
  name: name,
  osmId: 1,
  stationType: type,
  city: city,
  country: 'USA',
  latitude: 41.8,
  longitude: -87.6,
);

void main() {
  late MockTripBloc tripBloc;
  late MockPeopleBloc peopleBloc;

  setUpAll(() {
    registerFallbackValue(const ClearTrip());
    registerFallbackValue(UpdatePerson(_ada));
  });

  setUp(() {
    tripBloc = MockTripBloc();
    peopleBloc = MockPeopleBloc();
    when(() => tripBloc.state).thenReturn(const TripState());
    when(() => peopleBloc.state).thenReturn(const PeopleLoaded([]));
  });

  /// Opens the modal the way the map does, so closing it has a route to pop.
  Future<void> openModal(
    WidgetTester tester,
    List<dynamic> items, {
    VoidCallback? onZoom,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TripBloc>.value(value: tripBloc),
          BlocProvider<PeopleBloc>.value(value: peopleBloc),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      UnifiedClusterModal(items: items, onZoom: onZoom),
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

  group('header', () {
    testWidgets('counts a single item', (tester) async {
      await openModal(tester, [_ada], onZoom: () {});

      expect(find.text('1 Item Here'), findsOneWidget);
      // Nothing to zoom into for one item.
      expect(find.text('Zoom to Area'), findsNothing);
    });

    testWidgets('counts several items and offers to zoom', (tester) async {
      var zooms = 0;
      await openModal(tester, [_ada, _sfo, _station()], onZoom: () => zooms++);

      expect(find.text('3 Items Here'), findsOneWidget);
      await tester.tap(find.text('Zoom to Area'));
      expect(zooms, 1);
    });

    testWidgets('hides zoom without a handler', (tester) async {
      await openModal(tester, [_ada, _sfo]);
      expect(find.text('Zoom to Area'), findsNothing);
    });

    testWidgets('skips items of an unknown type', (tester) async {
      await openModal(tester, ['not a map item', _sfo]);

      expect(find.text('2 Items Here'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('not a map item'), findsNothing);
    });
  });

  group('person row', () {
    testWidgets('shows initials, name and tag', (tester) async {
      await openModal(tester, [_ada]);

      expect(find.text('AL'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('FRIEND'), findsOneWidget);
    });

    testWidgets('adds the person as a new stop', (tester) async {
      await openModal(tester, [_ada]);

      await tester.tap(find.byTooltip('Add as New Stop'));
      await tester.pump();

      verify(() => tripBloc.add(AddStop(_ada))).called(1);
      expect(find.text('Added Ada as new stop'), findsOneWidget);
    });

    testWidgets('does not offer to add someone already on the trip', (
      tester,
    ) async {
      when(() => tripBloc.state).thenReturn(
        TripState(
          stops: [
            TripStop(
              location: const LatLng(0, 0),
              sequenceOrder: 0,
              people: [_ada],
            ),
          ],
        ),
      );
      await openModal(tester, [_ada]);

      expect(find.byTooltip('Add as New Stop'), findsNothing);
      // No hub stop on the trip, so nothing to link to either.
      expect(find.byTooltip('Link to Stop'), findsNothing);
    });

    testWidgets('lists only airport and station stops to link to', (
      tester,
    ) async {
      when(() => tripBloc.state).thenReturn(
        TripState(
          stops: [
            TripStop(
              location: const LatLng(0, 0),
              sequenceOrder: 0,
              airport: _sfo,
            ),
            const TripStop(location: LatLng(1, 1), sequenceOrder: 1),
            TripStop(
              location: const LatLng(2, 2),
              sequenceOrder: 2,
              station: _station(),
            ),
          ],
        ),
      );
      await openModal(tester, [_ada]);

      await tester.tap(find.byTooltip('Link to Stop'));
      await tester.pumpAndSettle();

      expect(find.text('A: Airport SFO'), findsOneWidget);
      expect(find.text('C: Station Union Station'), findsOneWidget);
      expect(find.byType(PopupMenuItem<int>), findsNWidgets(2));
    });

    testWidgets('linking dispatches the stop index and offers a preference', (
      tester,
    ) async {
      final station = _station();
      when(() => tripBloc.state).thenReturn(
        TripState(
          stops: [
            const TripStop(location: LatLng(1, 1), sequenceOrder: 0),
            TripStop(
              location: const LatLng(2, 2),
              sequenceOrder: 1,
              station: station,
            ),
          ],
        ),
      );
      await openModal(tester, [_ada]);

      await tester.tap(find.byTooltip('Link to Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B: Station Union Station'));
      await tester.pumpAndSettle();

      verify(() => tripBloc.add(LinkPersonToStop(_ada, 1))).called(1);
      expect(find.text('Linked Ada to stop B'), findsOneWidget);
      expect(find.text('Set as Preferred'), findsOneWidget);
    });

    testWidgets('setting the linked hub as preferred updates the person', (
      tester,
    ) async {
      final station = _station();
      when(() => tripBloc.state).thenReturn(
        TripState(
          stops: [
            TripStop(
              location: const LatLng(2, 2),
              sequenceOrder: 0,
              station: station,
            ),
          ],
        ),
      );
      await openModal(tester, [_ada]);

      await tester.tap(find.byTooltip('Link to Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A: Station Union Station'));
      await tester.pumpAndSettle();
      // The toast is drawn by the map's scaffold, beneath the sheet; dismiss
      // the sheet to reach its action.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set as Preferred'));
      await tester.pumpAndSettle();

      final event =
          verify(() => peopleBloc.add(captureAny())).captured.single
              as UpdatePerson;
      expect(event.person.id, 'p1');
      expect(event.person.preferredStationId, '7');
      expect(event.person.preferredStation, same(station));
      expect(event.person.preferredAirportId, isNull);
    });

    testWidgets('opens the person after closing the modal', (tester) async {
      await openModal(tester, [_ada]);

      await tester.tap(find.text('Ada Lovelace'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(UnifiedClusterModal), findsNothing);
      expect(
        tester
            .widget<PersonDetailsScreen>(find.byType(PersonDetailsScreen))
            .personId,
        'p1',
      );
    });
  });

  group('airport row', () {
    testWidgets('shows the name, code and place', (tester) async {
      await openModal(tester, [_sfo]);

      expect(find.text('San Francisco International'), findsOneWidget);
      expect(find.text('SFO • San Francisco, USA'), findsOneWidget);
      expect(find.byIcon(Icons.flight), findsOneWidget);
    });

    testWidgets('adds the airport to the trip', (tester) async {
      await openModal(tester, [_sfo]);

      await tester.tap(find.byTooltip('Add to Trip'));
      await tester.pump();

      verify(() => tripBloc.add(AddAirportStop(_sfo))).called(1);
      expect(
        find.text('Added San Francisco International to trip'),
        findsOneWidget,
      );
    });

    testWidgets('swaps the modal for the airport sheet', (tester) async {
      await openModal(tester, [_sfo]);

      await tester.tap(find.text('San Francisco International'));
      await tester.pumpAndSettle();

      expect(find.byType(UnifiedClusterModal), findsNothing);
      expect(
        tester
            .widget<AirportBottomSheet>(find.byType(AirportBottomSheet))
            .airport,
        same(_sfo),
      );
    });
  });

  group('station row', () {
    for (final (type, label, icon) in [
      ('major_station', 'Major Station', Icons.train),
      ('commuter_rail_station', 'Commuter Rail', Icons.directions_railway),
      ('subway_station', 'Subway Station', Icons.subway),
      ('regional_station', 'Regional Station', Icons.train),
      ('tram_stop', 'tram_stop', Icons.train),
    ]) {
      testWidgets('labels a $type', (tester) async {
        await openModal(tester, [_station(type: type)]);

        expect(find.text('$label • Chicago'), findsOneWidget);
        expect(find.byIcon(icon), findsOneWidget);
      });
    }

    testWidgets('falls back when type and city are unknown', (tester) async {
      await openModal(tester, [_station(type: null, city: null)]);

      expect(find.text('Station • Unknown City'), findsOneWidget);
    });

    testWidgets('adds the station to the trip', (tester) async {
      final station = _station();
      await openModal(tester, [station]);

      await tester.tap(find.byTooltip('Add to Trip'));
      await tester.pump();

      verify(() => tripBloc.add(AddStationStop(station))).called(1);
      expect(find.text('Added Union Station to trip'), findsOneWidget);
    });

    testWidgets('swaps the modal for the station sheet', (tester) async {
      final station = _station();
      await openModal(tester, [station]);

      await tester.tap(find.text('Union Station'));
      await tester.pumpAndSettle();

      expect(find.byType(UnifiedClusterModal), findsNothing);
      expect(
        tester
            .widget<StationBottomSheet>(find.byType(StationBottomSheet))
            .station,
        same(station),
      );
    });
  });
}
