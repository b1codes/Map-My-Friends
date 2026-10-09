import 'package:flutter/material.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/components/map/horizontal_trip_planner.dart';
import 'package:map_my_friends/components/map/map_controls.dart';
import 'package:map_my_friends/components/map/map_settings_button.dart';
import 'package:map_my_friends/components/map/map_settings_modal.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/fixtures.dart';
import '../../../support/map_backdrop.dart';
import '../../../support/stage.dart';
import '../../../support/story_scope.dart';

// --- MapControls --------------------------------------------------------------

@widgetbook.UseCase(
  name: 'Over the map',
  type: MapControls,
  path: '[Components]/map',
)
Widget mapControlsOverMap(BuildContext context) {
  final modalVisible = context.knobs.boolean(
    label: 'Bottom modal visible',
    description: 'Lifts the controls clear of an open bottom sheet.',
    initialValue: false,
  );

  // The controls drive a live map. Switch the viewport to a landscape phone
  // to see the two groups lay out side by side.
  return StoryScope(
    child: Stage.route(
      child: MapBackdrop(
        builder: (context, controller) => MapControls(
          mapController: controller,
          isBottomModalVisible: modalVisible,
        ),
      ),
    ),
  );
}

// --- MapSettingsButton --------------------------------------------------------

@widgetbook.UseCase(
  name: 'Over the map (tap to open)',
  type: MapSettingsButton,
  path: '[Components]/map',
)
Widget mapSettingsButtonOverMap(BuildContext context) {
  return StoryScope(
    child: Stage.route(
      child: MapBackdrop(
        builder: (context, controller) =>
            const Stack(children: [MapSettingsButton()]),
      ),
    ),
  );
}

// --- MapSettingsModal ---------------------------------------------------------

@widgetbook.UseCase(
  name: 'Inline',
  type: MapSettingsModal,
  path: '[Components]/map',
)
Widget mapSettingsModalInline(BuildContext context) {
  final showAirports = context.knobs.boolean(
    label: 'Airports on',
    description: 'Initial value; the switches in the modal stay live.',
    initialValue: true,
  );
  final showStations = context.knobs.boolean(
    label: 'Stations on',
    initialValue: false,
  );
  final mapType = context.knobs.object.dropdown(
    label: 'Map type',
    options: MapType.values,
    labelBuilder: (t) => t.name,
  );

  return StoryScope(
    // Keyed so a knob change rebuilds the scope with the new starting
    // settings rather than leaving the modal's own edits in place.
    key: ValueKey((showAirports, showStations, mapType)),
    mapSettings: MapSettingsState(
      showAirports: showAirports,
      showStations: showStations,
      mapType: mapType,
    ),
    child: const Stage(
      alignment: Alignment.bottomCenter,
      padding: EdgeInsets.zero,
      child: MapSettingsModal(),
    ),
  );
}

// --- HorizontalTripPlanner ----------------------------------------------------

@widgetbook.UseCase(
  name: 'Planning a trip',
  type: HorizontalTripPlanner,
  path: '[Components]/map',
)
Widget horizontalTripPlannerPlanning(BuildContext context) {
  final stopCount = context.knobs.int.slider(
    label: 'Stops',
    description: 'At zero the planner hides itself.',
    initialValue: 4,
    max: 4,
  );
  final optimizing = context.knobs.boolean(
    label: 'Optimizing',
    initialValue: false,
  );
  final stops = Fixtures.planningTrip.stops.take(stopCount).toList();

  return StoryScope(
    trip: TripState(
      stops: stops,
      isOptimizing: optimizing,
      userTrips: Fixtures.trips,
    ),
    child: Stage.route(
      child: MapBackdrop(
        builder: (context, controller) =>
            const Stack(children: [HorizontalTripPlanner()]),
      ),
    ),
  );
}
