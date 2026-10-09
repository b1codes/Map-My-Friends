import 'package:flutter/material.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/components/shared/nearby_airports_section.dart';
import 'package:map_my_friends/components/shared/nearby_stations_section.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/fixtures.dart';
import '../../../support/stage.dart';
import '../../../support/story_scope.dart';

enum _Load { loaded, empty, loading, error }

_Load _loadKnob(BuildContext context) => context.knobs.object.dropdown(
  label: 'State',
  options: _Load.values,
  labelBuilder: (s) => s.name,
);

DistanceUnit _unitKnob(BuildContext context) => context.knobs.object.dropdown(
  label: 'Distance unit',
  description: 'Read from the app-wide map settings.',
  options: DistanceUnit.values,
  labelBuilder: (u) => u.name,
);

@widgetbook.UseCase(
  name: 'States',
  type: NearbyAirportsSection,
  path: '[Components]/shared',
)
Widget nearbyAirportsStates(BuildContext context) {
  final AirportState state = switch (_loadKnob(context)) {
    _Load.loaded => NearestAirportsLoaded(Fixtures.airports),
    _Load.empty => const NearestAirportsLoaded([]),
    _Load.loading => AirportLoading(),
    _Load.error => const AirportError('Could not reach the server'),
  };
  final unit = _unitKnob(context);

  return StoryScope(
    nearbyAirports: state,
    mapSettings: MapSettingsState(distanceUnit: unit),
    child: const Stage(
      child: GlassContainer(
        child: NearbyAirportsSection(latitude: 40.7128, longitude: -74.0060),
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'States',
  type: NearbyStationsSection,
  path: '[Components]/shared',
)
Widget nearbyStationsStates(BuildContext context) {
  final StationState state = switch (_loadKnob(context)) {
    _Load.loaded => NearestStationsLoaded(Fixtures.stations.take(3).toList()),
    _Load.empty => const NearestStationsLoaded([]),
    _Load.loading => StationLoading(),
    _Load.error => const StationError('Could not reach the server'),
  };
  final unit = _unitKnob(context);

  return StoryScope(
    nearbyStations: state,
    mapSettings: MapSettingsState(distanceUnit: unit),
    child: const Stage(
      child: GlassContainer(
        child: NearbyStationsSection(latitude: 40.7128, longitude: -74.0060),
      ),
    ),
  );
}
