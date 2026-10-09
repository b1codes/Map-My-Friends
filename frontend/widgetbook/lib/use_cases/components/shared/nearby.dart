import 'package:flutter/material.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/components/shared/nearby_airports_section.dart';
import 'package:map_my_friends/components/shared/nearby_stations_section.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/fake_blocs.dart';
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

/// Owns the bloc a section is handed, so it is closed with the entry.
class _Seeded<B extends InertBloc<Object?, S>, S> extends StatefulWidget {
  const _Seeded({
    required this.create,
    required this.state,
    required this.builder,
  });

  final B Function(S state) create;
  final S state;
  final Widget Function(B bloc) builder;

  @override
  State<_Seeded<B, S>> createState() => _SeededState<B, S>();
}

class _SeededState<B extends InertBloc<Object?, S>, S>
    extends State<_Seeded<B, S>> {
  late final B _bloc = widget.create(widget.state);

  @override
  void didUpdateWidget(_Seeded<B, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bloc.seed(widget.state);
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_bloc);
}

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
    mapSettings: MapSettingsState(distanceUnit: unit),
    child: Stage(
      child: GlassContainer(
        child: _Seeded<StoryAirportBloc, AirportState>(
          create: StoryAirportBloc.new,
          state: state,
          builder: (bloc) => NearbyAirportsSection(
            latitude: 40.7128,
            longitude: -74.0060,
            bloc: bloc,
          ),
        ),
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
    mapSettings: MapSettingsState(distanceUnit: unit),
    child: Stage(
      child: GlassContainer(
        child: _Seeded<StoryStationBloc, StationState>(
          create: StoryStationBloc.new,
          state: state,
          builder: (bloc) => NearbyStationsSection(
            latitude: 40.7128,
            longitude: -74.0060,
            bloc: bloc,
          ),
        ),
      ),
    ),
  );
}
