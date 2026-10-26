// Trips: building a trip in the planner from the people on the map, saving
// it, finding it again in My Trips, changing it, and deleting it, against the
// real trips API. Driving routes between people come from OSRM, answered by
// the stub server.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:map_my_friends/components/map/horizontal_trip_planner.dart';
import 'package:map_my_friends/components/people/person_card.dart';
import 'package:map_my_friends/components/shared/thermal_button.dart';

import '../support/e2e.dart';

/// The name the planner gives a trip saved today.
String get draftTripName =>
    'Draft Trip ${DateFormat('yyyy-MM-dd').format(DateTime.now())}';

/// A journey user with three people to plan around. Grace (Chicago) and Alan
/// (Boston) are person-only stops, so the leg between them is a driving
/// route. Ada (London) prefers her nearest airport, so her stop is a hub.
class TripWorld {
  TripWorld._(this.user, this.adaAirportCode);

  final JourneyUser user;
  final String adaAirportCode;

  static Future<TripWorld> create(String prefix) async {
    final user = await JourneyUser.registered(prefix);
    final api = await user.api();

    final nearest = await api.get(
      'airports/nearest/',
      queryParameters: {'lat': '51.5074', 'lon': '-0.1278', 'count': '1'},
    );
    final airport = (nearest.data['features'] as List).first as Map;

    await user.addPerson(
      firstName: 'Grace',
      lastName: 'Hopper',
      city: 'Chicago',
      state: 'IL',
    );
    await user.addPerson(
      firstName: 'Alan',
      lastName: 'Turing',
      city: 'Boston',
      state: 'MA',
    );
    // addPerson sets no hub; Ada's preferred airport makes her stop a hub.
    await api.post(
      'people/',
      data: {
        'first_name': 'Ada',
        'last_name': 'Lovelace',
        'city': 'London',
        'state': 'England',
        'country': 'UK',
        'tag': 'FRIEND',
        'preferred_airport': airport['id'],
      },
    );

    return TripWorld._(
      user,
      (airport['properties'] as Map)['iata_code'] as String,
    );
  }

  /// The trips the API holds for this user.
  Future<List<Map<String, dynamic>>> savedTrips() async {
    final response = await (await user.api()).get('trips/');
    return (response.data as List).cast<Map<String, dynamic>>();
  }
}

/// The trip planner strip on the map: present while it has stops.
Finder get planner => find.bySemanticsLabel('Save Trip');

/// A stop in the planner strip, by the name it shows.
Finder plannerStop(String name) => find.descendant(
  of: find.byType(HorizontalTripPlanner),
  matching: find.text(name),
);

/// A trip card in My Trips.
Finder tripCard(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(ListTile));

/// Opens [fullName] from the People tab and adds them to the planner.
Future<void> addToPlanner(WidgetTester tester, String fullName) async {
  await goToTab(tester, 'People');
  await tapOn(
    tester,
    find.ancestor(of: find.text(fullName), matching: find.byType(PersonCard)),
  );
  await tapText(tester, 'Add to Trip Planner');
  await pumpUntil(tester, toast('to trip'));
  await goBack(tester);
  await pumpUntilGone(tester, find.text('Add to Trip Planner'));
}

/// Builds Grace → Alan → Ada in the planner and saves it from the map.
Future<void> planAndSaveTrip(WidgetTester tester, TripWorld world) async {
  await addToPlanner(tester, 'Grace Hopper');
  await addToPlanner(tester, 'Alan Turing');
  await addToPlanner(tester, 'Ada Lovelace');

  await goToTab(tester, 'Map');
  await tapOn(tester, planner);
  // Saving lists the trip; wait for the API round trip to land.
  await goToTab(tester, 'Trips');
  await pumpUntil(tester, tripCard(draftTripName), reason: 'the saved trip');
}

/// Opens [trip]'s ⋮ menu in My Trips and picks [action].
Future<void> tripMenu(WidgetTester tester, String trip, String action) async {
  await tapOn(
    tester,
    find.descendant(of: tripCard(trip), matching: find.byIcon(Icons.more_vert)),
  );
  await tapText(tester, action);
  await settle(tester);
}

void main() {
  setUpE2E();

  group('Trips', () {
    journey('a trip planned from people is saved with its people and hubs', (
      tester,
    ) async {
      final world = await TripWorld.create('plan');
      await launchSignedIn(tester, world.user);

      await planAndSaveTrip(tester, world);
      expect(find.textContaining('3 stops'), findsOneWidget);
      expect(find.text('Drafts'), findsOneWidget);

      // The planner now shows the trip as the API returned it. Each stop's
      // people and hub come from the response's people_detail and
      // airport_detail, so the names prove the API sent them back.
      await goToTab(tester, 'Map');
      await pumpUntil(tester, plannerStop('Grace'));
      expect(plannerStop('Alan'), findsOneWidget);
      expect(plannerStop(world.adaAirportCode), findsOneWidget);

      final trips = await world.savedTrips();
      expect(trips, hasLength(1));
      final stops = trips.single['stops'] as List;
      expect(stops, hasLength(3));
      expect((stops[2] as Map)['airport'], isNotNull);
      expect((stops[2] as Map)['people'], hasLength(1));
    });

    journey('saved trips are listed again after the app is reopened', (
      tester,
    ) async {
      final world = await TripWorld.create('reopen');
      await launchSignedIn(tester, world.user);
      await planAndSaveTrip(tester, world);

      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(tester, mainShell);
      await goToTab(tester, 'Trips');
      await pumpUntil(tester, tripCard(draftTripName));

      // Opening a draft loads it into the planner with its people and hub.
      await tapOn(tester, tripCard(draftTripName));
      await pumpUntil(tester, plannerStop('Grace'));
      expect(plannerStop('Alan'), findsOneWidget);
      expect(plannerStop(world.adaAirportCode), findsOneWidget);
    });

    journey('the leg between two people follows the OSRM driving route', (
      tester,
    ) async {
      final world = await TripWorld.create('route');
      await launchSignedIn(tester, world.user);
      await E2EApi.clearStubLog();

      await addToPlanner(tester, 'Grace Hopper');
      await addToPlanner(tester, 'Alan Turing');
      await goToTab(tester, 'Map');
      await pumpUntil(tester, plannerStop('Alan'));

      final polyline = find.byWidgetPredicate((w) => w is PolylineLayer);
      await pumpUntil(tester, polyline, reason: 'the route on the map');

      final routeCalls = (await E2EApi.stubLog())
          .where((r) => (r['path'] as String).startsWith('/route/'))
          .map((r) => r['path'])
          .toList();
      expect(routeCalls, [
        '/route/v1/driving/-87.6298,41.8781;-71.0589,42.3601',
      ]);

      // A straight-line fallback would be just the two stops; the stub's
      // route goes through a third point.
      final layer = tester.widget<PolylineLayer>(polyline);
      expect(layer.polylines.single.points.length, greaterThan(2));
    });

    journey('a saved trip can be changed and the change is kept', (
      tester,
    ) async {
      final world = await TripWorld.create('edit');
      await launchSignedIn(tester, world.user);
      await planAndSaveTrip(tester, world);

      // Change its stops: reopen it in the planner, add one more stop, and
      // save again.
      await tapOn(tester, tripCard(draftTripName));
      await pumpUntil(tester, plannerStop('Grace'));
      await addToPlanner(tester, 'Grace Hopper');
      await goToTab(tester, 'Map');
      await tapOn(tester, planner);
      await goToTab(tester, 'Trips');
      await pumpUntil(tester, find.textContaining('4 stops'));

      // Saving a reopened trip updates it rather than adding a copy.
      var trips = await world.savedTrips();
      expect(trips, hasLength(1));
      expect(trips.single['stops'], hasLength(4));

      // Booking it moves it to the Booked section.
      await tripMenu(tester, draftTripName, 'Update Status');
      await tapText(tester, 'BOOKED');
      await pumpUntil(tester, find.text('Booked'));
      expect(find.text('Drafts'), findsNothing);

      trips = await world.savedTrips();
      expect(trips, hasLength(1));
      expect(trips.single['status'], 'BOOKED');
      expect(trips.single['stops'], hasLength(4));

      // A booked trip opens its itinerary rather than the planner.
      await tapOn(tester, tripCard(draftTripName));
      await pumpUntil(tester, find.textContaining('Grace'));
    });

    journey('booking a trip that isn\'t open in the planner keeps its stops', (
      tester,
    ) async {
      final world = await TripWorld.create('status');
      await launchSignedIn(tester, world.user);
      await planAndSaveTrip(tester, world);

      await goToTab(tester, 'Map');
      await tapOn(tester, find.bySemanticsLabel('Clear Trip'));
      await pumpUntilGone(tester, planner);

      await goToTab(tester, 'Trips');
      await tripMenu(tester, draftTripName, 'Update Status');
      await tapText(tester, 'BOOKED');
      await pumpUntil(tester, find.text('Booked'));

      final trips = await world.savedTrips();
      expect(trips, hasLength(1));
      expect(trips.single['status'], 'BOOKED');
      expect(trips.single['stops'], hasLength(3));
    });

    journey('a deleted trip is gone for good', (tester) async {
      final world = await TripWorld.create('delete');
      await launchSignedIn(tester, world.user);
      await planAndSaveTrip(tester, world);

      await tripMenu(tester, draftTripName, 'Delete');
      await pumpUntil(tester, find.text('Delete Trip'));
      await tapOn(tester, find.widgetWithText(ThermalButton, 'Delete'));

      await pumpUntil(tester, find.text('No Trips Yet'));
      expect(await world.savedTrips(), isEmpty);

      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(tester, mainShell);
      await goToTab(tester, 'Trips');
      await pumpUntil(tester, find.text('No Trips Yet'));
    });
  });
}
