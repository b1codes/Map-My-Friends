import 'package:flutter/material.dart';
import 'package:map_my_friends/components/map/map_bottom_sheets.dart';
import 'package:map_my_friends/components/map/unified_cluster_modal.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/fixtures.dart';
import '../../../support/stage.dart';
import '../../../support/story_scope.dart';

/// Sheets dock to the bottom of the map in the app, so they do here too.
Widget _sheet(Widget child) => StoryScope(
  child: Stage(
    alignment: Alignment.bottomCenter,
    padding: EdgeInsets.zero,
    child: child,
  ),
);

// --- AirportBottomSheet -------------------------------------------------------

@widgetbook.UseCase(
  name: 'Default',
  type: AirportBottomSheet,
  path: '[Components]/map',
)
Widget airportBottomSheetDefault(BuildContext context) {
  final airport = context.knobs.object.dropdown<Airport>(
    label: 'Airport',
    options: [...Fixtures.airports, Fixtures.fco],
    labelBuilder: (a) => '${a.iataCode} · ${a.airportType}',
  );
  return _sheet(AirportBottomSheet(airport: airport));
}

// --- StationBottomSheet -------------------------------------------------------

@widgetbook.UseCase(
  name: 'Default',
  type: StationBottomSheet,
  path: '[Components]/map',
)
Widget stationBottomSheetDefault(BuildContext context) {
  final station = context.knobs.object.dropdown<Station>(
    label: 'Station',
    description: 'One per station type; each has its own icon and colour.',
    options: Fixtures.stations,
    labelBuilder: (s) => '${s.name} · ${s.stationType}',
  );
  return _sheet(StationBottomSheet(station: station));
}

// --- BaseBottomSheet ----------------------------------------------------------

@widgetbook.UseCase(
  name: 'Playground',
  type: BaseBottomSheet,
  path: '[Components]/map',
)
Widget baseBottomSheetPlayground(BuildContext context) {
  final title = context.knobs.string(
    label: 'Title',
    initialValue: 'John F. Kennedy International Airport',
  );
  final subtitle = context.knobs.stringOrNull(
    label: 'Subtitle',
    initialValue: 'JFK / KJFK',
  );
  final location = context.knobs.string(
    label: 'Location',
    initialValue: 'New York, US',
  );
  final label = context.knobs.string(
    label: 'Type label',
    initialValue: 'Major Airport',
  );
  final color = context.knobs.color(
    label: 'Accent',
    initialValue: MapPalette.airport,
  );
  final canAdd = context.knobs.boolean(
    label: 'Add to trip',
    initialValue: true,
  );

  return _sheet(
    BaseBottomSheet(
      icon: Icons.flight,
      color: color,
      title: title,
      subtitle: subtitle,
      location: location,
      label: label,
      onAddToTrip: canAdd ? () {} : null,
    ),
  );
}

// --- UnifiedClusterModal ------------------------------------------------------

enum _Cluster { mixed, people, transit, single }

@widgetbook.UseCase(
  name: 'Cluster contents',
  type: UnifiedClusterModal,
  path: '[Components]/map',
)
Widget unifiedClusterModalContents(BuildContext context) {
  final cluster = context.knobs.object.dropdown(
    label: 'Contents',
    options: _Cluster.values,
    labelBuilder: (c) => c.name,
  );
  final zoomable = context.knobs.boolean(
    label: 'Zoom to area',
    description: 'Only offered for more than one item.',
    initialValue: true,
  );

  final List<Object> items = switch (cluster) {
    _Cluster.mixed => [
      Fixtures.sara,
      Fixtures.jfk,
      Fixtures.pennStation,
      Fixtures.mom,
    ],
    _Cluster.people => Fixtures.people,
    _Cluster.transit => [...Fixtures.airports, ...Fixtures.stations],
    _Cluster.single => [Fixtures.marco],
  };

  return StoryScope(
    // Sara is already a stop, so her row shows the "in trip" state.
    trip: Fixtures.planningTrip,
    child: Stage(
      alignment: Alignment.bottomCenter,
      padding: EdgeInsets.zero,
      child: UnifiedClusterModal(items: items, onZoom: zoomable ? () {} : null),
    ),
  );
}
