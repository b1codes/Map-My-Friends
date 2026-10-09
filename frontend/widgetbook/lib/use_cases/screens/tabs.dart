import 'package:flutter/material.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_state.dart';
import 'package:map_my_friends/bloc/pulse/pulse_bloc.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/screens/map/map_screen.dart';
import 'package:map_my_friends/screens/people/people_screen.dart';
import 'package:map_my_friends/screens/profile/me_screen.dart';
import 'package:map_my_friends/screens/pulse/pulse_screen.dart';
import 'package:map_my_friends/screens/trips/trips_screen.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/fixtures.dart';
import '../../support/stage.dart';
import '../../support/story_scope.dart';

// The five tab screens. In the app they render inside the shell, which owns
// the Ambient Field and backdrop group; Stage.screen stands in for it. See the
// Shell entry for them with the navigation chrome.

enum _Load { loaded, empty, loading, error }

_Load _loadKnob(BuildContext context) => context.knobs.object.dropdown(
  label: 'State',
  options: _Load.values,
  labelBuilder: (s) => s.name,
);

// --- Map ----------------------------------------------------------------------

@widgetbook.UseCase(name: 'Default', type: MapScreen, path: '[Screens]/map')
Widget mapScreenDefault(BuildContext context) {
  final people = context.knobs.boolean(label: 'People', initialValue: true);
  final airports = context.knobs.boolean(
    label: 'Airports layer',
    initialValue: false,
  );
  final stations = context.knobs.boolean(
    label: 'Stations layer',
    initialValue: false,
  );
  final planning = context.knobs.boolean(
    label: 'Trip in progress',
    description: 'Shows the planner along the bottom of the map.',
    initialValue: false,
  );
  final mapType = context.knobs.object.dropdown(
    label: 'Map type',
    options: MapType.values,
    labelBuilder: (t) => t.name,
  );

  return StoryScope(
    // MapScreen copies the app-wide settings into its own cubit once, on
    // first build; keying the scope is what makes these knobs reapply.
    key: ValueKey((airports, stations, mapType)),
    people: PeopleLoaded(people ? Fixtures.people : const []),
    airports: MapAirportsLoaded(Fixtures.airports),
    stations: MapStationsLoaded(Fixtures.stations),
    trip: planning ? Fixtures.planningTrip : const TripState(),
    mapSettings: MapSettingsState(
      showAirports: airports,
      showStations: stations,
      mapType: mapType,
    ),
    child: const Stage.route(child: MapScreen()),
  );
}

// --- People -------------------------------------------------------------------

@widgetbook.UseCase(
  name: 'States',
  type: PeopleScreen,
  path: '[Screens]/people',
)
Widget peopleScreenStates(BuildContext context) {
  final PeopleState state = switch (_loadKnob(context)) {
    _Load.loaded => PeopleLoaded(Fixtures.people),
    _Load.empty => const PeopleLoaded([]),
    _Load.loading => PeopleLoading(),
    _Load.error => const PeopleError('Could not reach the server'),
  };

  // Tap a card for Person details, then Edit — the whole flow runs here.
  return StoryScope(
    people: state,
    child: const Stage.screen(child: PeopleScreen()),
  );
}

// --- Pulse --------------------------------------------------------------------

@widgetbook.UseCase(name: 'States', type: PulseScreen, path: '[Screens]/pulse')
Widget pulseScreenStates(BuildContext context) {
  final PulseState state = switch (_loadKnob(context)) {
    _Load.loaded => Fixtures.pulseLoaded(),
    _Load.empty => const PulseLoaded(people: [], logs: []),
    _Load.loading => PulseLoading(),
    _Load.error => const PulseError('Could not reach the server'),
  };

  return StoryScope(
    pulse: state,
    // Pinned to the fixtures' "today", so recency reads the same every run.
    child: Stage.screen(child: PulseScreen(now: Fixtures.now)),
  );
}

// --- Trips --------------------------------------------------------------------

@widgetbook.UseCase(name: 'States', type: TripsScreen, path: '[Screens]/trips')
Widget tripsScreenStates(BuildContext context) {
  final TripState state = switch (context.knobs.object.dropdown(
    label: 'State',
    options: const [_Load.loaded, _Load.empty, _Load.loading],
    labelBuilder: (s) => s.name,
  )) {
    _Load.empty => const TripState(),
    _Load.loading => const TripState(isLoading: true),
    _ => TripState(userTrips: Fixtures.trips),
  };

  return StoryScope(
    trip: state,
    child: Stage.screen(child: TripsScreen(onNavigateToMap: () {})),
  );
}

// --- Me -----------------------------------------------------------------------

@widgetbook.UseCase(name: 'States', type: MeScreen, path: '[Screens]/profile')
Widget meScreenStates(BuildContext context) {
  final ProfileState state = switch (context.knobs.object.dropdown(
    label: 'State',
    options: const ['loaded', 'new account', 'saving', 'loading', 'error'],
  )) {
    'new account' => const ProfileLoaded(
      username: 'alex',
      email: 'alex@example.com',
    ),
    'saving' => ProfileUpdating(),
    'loading' => ProfileLoading(),
    'error' => const ProfileError(message: 'Could not load your profile'),
    _ => Fixtures.profile,
  };

  return StoryScope(
    profile: state,
    child: const Stage.screen(child: MeScreen()),
  );
}
