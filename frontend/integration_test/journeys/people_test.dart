// People: adding someone (the API geocodes their address), editing them,
// and deleting them, on the real API. Addresses resolve through the stub
// geocoder (docker/e2e-stubs), which knows a fixed set of cities and finds
// nothing for any other.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:map_my_friends/components/people/person_card.dart';

import '../support/e2e.dart';

/// The People tab's add action (a header icon with a tooltip).
final addPersonButton = find.byTooltip('Add person');

final savePersonButton = find.widgetWithText(FilledButton, 'Save Person');

/// The People list's card for [name], tapped at its centre. Not the name
/// itself: at some window heights the grid slides under the navigation rail
/// and the name sits beneath it (a known layout bug, reported separately).
Finder personCard(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(PersonCard));

/// A row on Pulse, whose roster sits below the calendar and is usually
/// scrolled out of view until [tapOn] brings it in.
Finder rosterName(String name) => find.text(name, skipOffstage: false);

/// Fills the person form's address with a city, state and country.
Future<void> enterAddress(
  WidgetTester tester, {
  required String city,
  required String state,
  required String country,
}) async {
  await enterField(tester, 'City (Required)', city);
  await enterField(tester, 'State (Required)', state);
  await enterField(tester, 'Country (Required)', country);
}

/// The people the API holds for [user], as GeoJSON features.
Future<List<Map<String, dynamic>>> peopleOnServer(JourneyUser user) async {
  final api = await user.api();
  final response = await api.get('people/');
  return (response.data['features'] as List).cast<Map<String, dynamic>>();
}

/// Creates a person for [api]'s user through the API (geocoded by the stub,
/// so [city] must be one it knows). Returns the new person's id.
Future<String> seedPerson(
  Dio api, {
  required String firstName,
  required String lastName,
  String city = 'London',
  String state = 'England',
  String country = 'UK',
  String tag = 'FRIEND',
  int? cadenceDays,
}) async {
  final response = await api.post(
    'people/',
    data: {
      'first_name': firstName,
      'last_name': lastName,
      'city': city,
      'state': state,
      'country': country,
      'tag': tag,
      'contact_cadence_days': ?cadenceDays,
    },
  );
  return response.data['id'] as String;
}

void main() {
  setUpE2E();

  group('People', () {
    journey('a person is added, edited, and deleted', (tester) async {
      final user = await JourneyUser.registered('people');
      await launchSignedIn(tester, user);
      await goToTab(tester, 'People');
      await pumpUntil(tester, find.text('No Friends Added Yet'));

      // Add: the API geocodes London through the stub.
      await tapOn(tester, addPersonButton);
      await enterField(tester, 'First Name', 'Ada');
      await enterField(tester, 'Last Name', 'Lovelace');
      await enterAddress(
        tester,
        city: 'London',
        state: 'England',
        country: 'UK',
      );
      await tapOn(tester, savePersonButton);

      await pumpUntil(tester, find.text('Ada Lovelace'));
      expect(find.text('London, England'), findsOneWidget);
      expect(find.text('1 person'), findsOneWidget);

      var saved = await peopleOnServer(user);
      expect(saved, hasLength(1));
      expect(saved.single['geometry']['coordinates'], [-0.1278, 51.5074]);
      expect(saved.single['properties']['timezone'], 'Europe/London');

      // Edit: moving them re-geocodes the new address.
      await tapOn(tester, personCard('Ada Lovelace'));
      await pumpUntil(tester, find.byTooltip('Edit'));
      await tapOn(tester, find.byTooltip('Edit'));
      await pumpUntil(tester, savePersonButton);
      await enterAddress(
        tester,
        city: 'Paris',
        state: 'Ile-de-France',
        country: 'France',
      );
      await tapOn(tester, savePersonButton);

      // Back on the details screen, which shows the new address.
      await pumpUntil(tester, find.text('Paris, Ile-de-France France'));

      saved = await peopleOnServer(user);
      expect(saved.single['properties']['city'], 'Paris');
      expect(saved.single['geometry']['coordinates'], [2.3522, 48.8566]);
      expect(saved.single['properties']['timezone'], 'Europe/Paris');

      // The edit is what the app shows when the user comes back later.
      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(tester, mainShell);
      await goToTab(tester, 'People');
      await pumpUntil(tester, find.text('Paris, Ile-de-France'));
      expect(find.text('London, England'), findsNothing);

      // Delete, after confirming.
      await tapOn(tester, personCard('Ada Lovelace'));
      await tapOn(tester, find.byTooltip('Delete'));
      await pumpUntil(tester, find.text('Delete Ada?'));
      await tapOn(tester, find.text('Delete').last);
      await pumpUntil(tester, find.text('No Friends Added Yet'));
      expect(await peopleOnServer(user), isEmpty);

      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(tester, mainShell);
      await goToTab(tester, 'People');
      await pumpUntil(tester, find.text('No Friends Added Yet'));
    });

    journey(
      'an address the geocoder cannot find is refused with the reason',
      (tester) async {
        final user = await JourneyUser.registered('nowhere');
        await launchSignedIn(tester, user);
        await goToTab(tester, 'People');
        await pumpUntil(tester, find.text('No Friends Added Yet'));

        await tapOn(tester, addPersonButton);
        await enterField(tester, 'First Name', 'Nemo');
        await enterField(tester, 'Last Name', 'Nobody');
        await enterAddress(
          tester,
          city: 'Atlantis',
          state: 'Deep',
          country: 'Ocean',
        );
        await tapOn(tester, savePersonButton);

        // The API's reason, not a generic failure.
        await pumpUntil(
          tester,
          find.textContaining('Could not geocode address: Atlantis'),
          reason: "the API's geocoding error",
        );
        expect(await peopleOnServer(user), isEmpty);
      },
      skip:
          'Known bug: a failed add replaces the People list with '
          '"Couldn\'t load your people" and a raw DioException, not the '
          "API's reason (ClickUp 86bcrpgwe)",
    );

    journey('people saved earlier are listed after signing in', (tester) async {
      final user = await JourneyUser.registered('returning');
      final api = await user.api();
      await seedPerson(api, firstName: 'Grace', lastName: 'Hopper');

      await launchSignedIn(tester, user);
      await goToTab(tester, 'People');
      await pumpUntil(tester, find.text('Grace Hopper'));
      expect(find.text('No Friends Added Yet'), findsNothing);
    });
  });

  group('Keeping in touch', () {
    journey('logging a contact shows on Pulse and is kept', (tester) async {
      final user = await JourneyUser.registered('logcontact');
      final api = await user.api();
      final personId = await seedPerson(
        api,
        firstName: 'Ada',
        lastName: 'Lovelace',
      );

      await launchSignedIn(tester, user);
      await goToTab(tester, 'Pulse');
      await pumpUntil(tester, rosterName('Ada Lovelace'));
      expect(find.text('Start your first touchpoint'), findsOneWidget);
      expect(rosterName('No contact logged yet'), findsOneWidget);
      expect(rosterName('Not yet logged'), findsOneWidget);

      await tapOn(tester, rosterName('Ada Lovelace'));
      await pumpUntil(tester, find.text('Log contact'));
      await tapText(tester, 'Log call');

      await pumpUntil(tester, toast('Logged call with Ada'));
      await pumpUntil(tester, rosterName('Contacted today'));
      expect(find.text("You're all caught up"), findsOneWidget);
      expect(
        find.textContaining('In touch', skipOffstage: false),
        findsOneWidget,
      );

      final body = (await api.get('contact-logs/')).data;
      final logs = (body is Map ? body['results'] : body) as List;
      expect(logs, hasLength(1));
      expect(logs.single['person'], personId);
      expect(logs.single['channel'], 'CALL');

      // Pulse reloads from the API on a later visit.
      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(tester, mainShell);
      await goToTab(tester, 'Pulse');
      await pumpUntil(tester, rosterName('Contacted today'));
      expect(rosterName('No contact logged yet'), findsNothing);
    });

    journey('changing how often to keep in touch is saved', (tester) async {
      final user = await JourneyUser.registered('cadence');
      final api = await user.api();
      final personId = await seedPerson(
        api,
        firstName: 'Ada',
        lastName: 'Lovelace',
        cadenceDays: 30,
      );

      await launchSignedIn(tester, user);
      await goToTab(tester, 'Pulse');
      await tapOn(tester, rosterName('Ada Lovelace'));
      await tapText(tester, 'Stay in touch every 30 days');
      // The steppers move a week at a time. Found by icon: their tooltips
      // are swapped (a known bug, reported separately).
      await tapOn(tester, find.byIcon(Icons.add));
      await pumpUntil(tester, find.text('Stay in touch every 37 days'));

      await _pumpUntilServer(() async {
        final person = (await api.get('people/$personId/')).data;
        return person['properties']['contact_cadence_days'] == 37;
      }, reason: 'contact_cadence_days 37 on the API');

      // Opening the sheet again later starts from the saved rhythm.
      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(tester, mainShell);
      await goToTab(tester, 'Pulse');
      await tapOn(tester, rosterName('Ada Lovelace'));
      await pumpUntil(tester, find.text('Stay in touch every 37 days'));
    });

    journey('Pulse puts the people most overdue for contact first', (
      tester,
    ) async {
      final user = await JourneyUser.registered('pulse');
      final api = await user.api();
      final now = DateTime.now().toUtc();

      // Weekly, last called a month ago: long overdue.
      final overdue = await seedPerson(
        api,
        firstName: 'Ada',
        lastName: 'Lovelace',
        cadenceDays: 7,
      );
      // Monthly, called two days ago: in touch.
      final recent = await seedPerson(
        api,
        firstName: 'Grace',
        lastName: 'Hopper',
        city: 'New York',
        state: 'NY',
        country: 'USA',
        cadenceDays: 30,
      );
      // Never contacted at all: first in line.
      await seedPerson(
        api,
        firstName: 'Alan',
        lastName: 'Turing',
        city: 'Chicago',
        state: 'IL',
        country: 'USA',
      );
      for (final (person, daysAgo) in [(overdue, 30), (recent, 2)]) {
        await api.post(
          'contact-logs/',
          data: {
            'person': person,
            'channel': 'CALL',
            'contacted_at': now
                .subtract(Duration(days: daysAgo))
                .toIso8601String(),
          },
        );
      }

      await launchSignedIn(tester, user);
      await goToTab(tester, 'Pulse');
      await pumpUntil(tester, rosterName('Grace Hopper'));

      expect(find.text('2 connections need a hello'), findsOneWidget);
      Finder chip(String label) =>
          find.textContaining(label, skipOffstage: false);
      expect(chip('Long overdue'), findsOneWidget);
      expect(chip('In touch'), findsOneWidget);
      expect(chip('Not yet logged'), findsOneWidget);

      double top(String name) => tester.getTopLeft(rosterName(name)).dy;
      expect(top('Alan Turing'), lessThan(top('Ada Lovelace')));
      expect(top('Ada Lovelace'), lessThan(top('Grace Hopper')));
    });
  });
}

/// Polls [check] until it holds: some saves (Pulse's cadence) aren't
/// awaited by anything on screen.
Future<void> _pumpUntilServer(
  Future<bool> Function() check, {
  required String reason,
}) async {
  final deadline = DateTime.now().add(defaultTimeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  fail('Timed out waiting for $reason.');
}
