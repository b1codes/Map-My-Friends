import 'package:flutter/material.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/screens/people/add_edit_person_screen.dart';
import 'package:map_my_friends/screens/people/person_details_screen.dart';
import 'package:map_my_friends/screens/settings/settings_screen.dart';
import 'package:map_my_friends/screens/trips/trip_details_screen.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/fixtures.dart';
import '../../support/stage.dart';
import '../../support/story_scope.dart';

// Screens the app only reaches by pushing, shown pushed: each has its back
// affordance, and popping lands on the screen it came from.

Person _personKnob(BuildContext context) => context.knobs.object.dropdown(
  label: 'Person',
  options: Fixtures.people,
  labelBuilder: (p) => '${p.firstName} ${p.lastName}'.trim(),
);

// --- Person details -----------------------------------------------------------

@widgetbook.UseCase(
  name: 'Default',
  type: PersonDetailsScreen,
  path: '[Screens]/people',
)
Widget personDetailsScreenDefault(BuildContext context) {
  final person = _personKnob(context);

  // The nearby airports and stations sections on this screen load live from
  // the API at ApiConfig.baseUrl; without the backend they show their error
  // state. Their own entries cover every state offline.
  return StoryScope(
    child: Stage.pushed(
      pushedFrom: 'People',
      child: PersonDetailsScreen(personId: person.id),
    ),
  );
}

// --- Add / edit person --------------------------------------------------------

@widgetbook.UseCase(
  name: 'Add',
  type: AddEditPersonScreen,
  path: '[Screens]/people',
)
Widget addPersonScreen(BuildContext context) {
  return const StoryScope(
    child: Stage.pushed(pushedFrom: 'People', child: AddEditPersonScreen()),
  );
}

@widgetbook.UseCase(
  name: 'Edit',
  type: AddEditPersonScreen,
  path: '[Screens]/people',
)
Widget editPersonScreen(BuildContext context) {
  final person = _personKnob(context);
  return StoryScope(
    child: Stage.pushed(
      pushedFrom: 'Person details',
      // Keyed: the form copies the person into its controllers once.
      child: AddEditPersonScreen(key: ValueKey(person.id), person: person),
    ),
  );
}

// --- Settings -----------------------------------------------------------------

@widgetbook.UseCase(
  name: 'Location permission',
  type: SettingsScreen,
  path: '[Screens]/settings',
)
Widget settingsScreenLocation(BuildContext context) {
  final LocationState location = switch (context.knobs.object.dropdown(
    label: 'Location',
    options: const ['granted', 'checking', 'denied', 'denied forever'],
  )) {
    'checking' => LocationLoading(),
    'denied' => LocationPermissionDenied(),
    'denied forever' => LocationPermissionDeniedForever(),
    _ => Fixtures.location,
  };

  // Theme and map preferences are live: they write to in-memory cubits.
  return StoryScope(
    location: location,
    child: const Stage.pushed(pushedFrom: 'Me', child: SettingsScreen()),
  );
}

// --- Trip details -------------------------------------------------------------

@widgetbook.UseCase(
  name: 'Default',
  type: TripDetailsScreen,
  path: '[Screens]/trips',
)
Widget tripDetailsScreenDefault(BuildContext context) {
  final trip = context.knobs.object.dropdown<Trip>(
    label: 'Trip',
    description:
        'The route line is fetched from the public OSRM server, so it needs '
        'a network connection; the itinerary does not.',
    options: Fixtures.trips,
    labelBuilder: (t) => '${t.name} (${t.status.value.toLowerCase()})',
  );

  return StoryScope(
    child: Stage.pushed(
      pushedFrom: 'Trips',
      child: TripDetailsScreen(key: ValueKey(trip.id), trip: trip),
    ),
  );
}
