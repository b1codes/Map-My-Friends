import 'package:flutter/material.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/auth/auth_state.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/main.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/fixtures.dart';
import '../../support/stage.dart';
import '../../support/story_scope.dart';

/// The shell with sample data in every tab.
Widget _populated({required Widget child, AuthState? auth}) => StoryScope(
  auth:
      auth ??
      const Authenticated(accessToken: 'catalog', refreshToken: 'catalog'),
  people: PeopleLoaded(Fixtures.people),
  airports: MapAirportsLoaded(Fixtures.airports),
  stations: MapStationsLoaded(Fixtures.stations),
  trip: TripState(userTrips: Fixtures.trips),
  child: child,
);

@widgetbook.UseCase(
  name: 'Navigation chrome',
  type: MainScreen,
  path: '[Screens]/shell',
)
Widget mainScreenShell(BuildContext context) {
  // One chrome, two layouts: a bottom bar where the window is narrow or
  // short, a rail otherwise. Switch viewports — a landscape phone is the case
  // that matters, since it is wide and still gets the bar.
  return _populated(child: const Stage.route(child: MainScreen()));
}

@widgetbook.UseCase(
  name: 'Auth gate',
  type: AuthWrapper,
  path: '[Screens]/shell',
)
Widget authWrapperGate(BuildContext context) {
  final AuthState auth = switch (context.knobs.object.dropdown(
    label: 'Auth state',
    description:
        'Checking shows the first frame the app ever draws: the Chromatic '
        'Pulse on its own.',
    options: const ['checking', 'signed out', 'signed in'],
  )) {
    'checking' => AuthInitial(),
    'signed in' => const Authenticated(
      accessToken: 'catalog',
      refreshToken: 'catalog',
    ),
    _ => const Unauthenticated(),
  };

  return _populated(
    auth: auth,
    child: const Stage.route(child: AuthWrapper()),
  );
}
