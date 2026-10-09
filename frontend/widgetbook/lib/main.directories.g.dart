// dart format width=80
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering

// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AppGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:map_my_friends_widgetbook/use_cases/components/map/map_chrome.dart'
    as _map_my_friends_widgetbook_use_cases_components_map_map_chrome;
import 'package:map_my_friends_widgetbook/use_cases/components/map/map_sheets.dart'
    as _map_my_friends_widgetbook_use_cases_components_map_map_sheets;
import 'package:map_my_friends_widgetbook/use_cases/components/map/markers.dart'
    as _map_my_friends_widgetbook_use_cases_components_map_markers;
import 'package:map_my_friends_widgetbook/use_cases/components/people_pulse.dart'
    as _map_my_friends_widgetbook_use_cases_components_people_pulse;
import 'package:map_my_friends_widgetbook/use_cases/components/shared/glass_container.dart'
    as _map_my_friends_widgetbook_use_cases_components_shared_glass_container;
import 'package:map_my_friends_widgetbook/use_cases/components/shared/glass_empty_state.dart'
    as _map_my_friends_widgetbook_use_cases_components_shared_glass_empty_state;
import 'package:map_my_friends_widgetbook/use_cases/components/shared/glass_header.dart'
    as _map_my_friends_widgetbook_use_cases_components_shared_glass_header;
import 'package:map_my_friends_widgetbook/use_cases/components/shared/glass_inlay.dart'
    as _map_my_friends_widgetbook_use_cases_components_shared_glass_inlay;
import 'package:map_my_friends_widgetbook/use_cases/components/shared/glass_surfaces.dart'
    as _map_my_friends_widgetbook_use_cases_components_shared_glass_surfaces;
import 'package:map_my_friends_widgetbook/use_cases/components/shared/inputs.dart'
    as _map_my_friends_widgetbook_use_cases_components_shared_inputs;
import 'package:map_my_friends_widgetbook/use_cases/components/shared/motion.dart'
    as _map_my_friends_widgetbook_use_cases_components_shared_motion;
import 'package:map_my_friends_widgetbook/use_cases/components/shared/nearby.dart'
    as _map_my_friends_widgetbook_use_cases_components_shared_nearby;
import 'package:map_my_friends_widgetbook/use_cases/components/shared/thermal.dart'
    as _map_my_friends_widgetbook_use_cases_components_shared_thermal;
import 'package:map_my_friends_widgetbook/use_cases/screens/auth.dart'
    as _map_my_friends_widgetbook_use_cases_screens_auth;
import 'package:map_my_friends_widgetbook/use_cases/screens/pushed.dart'
    as _map_my_friends_widgetbook_use_cases_screens_pushed;
import 'package:map_my_friends_widgetbook/use_cases/screens/shell.dart'
    as _map_my_friends_widgetbook_use_cases_screens_shell;
import 'package:map_my_friends_widgetbook/use_cases/screens/tabs.dart'
    as _map_my_friends_widgetbook_use_cases_screens_tabs;
import 'package:widgetbook/widgetbook.dart' as _widgetbook;

final directories = <_widgetbook.WidgetbookNode>[
  _widgetbook.WidgetbookCategory(
    name: 'Components',
    children: [
      _widgetbook.WidgetbookFolder(
        name: 'map',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'AirportBottomSheet',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_map_map_sheets
                        .airportBottomSheetDefault,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'BaseBottomSheet',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_map_map_sheets
                        .baseBottomSheetPlayground,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'CustomMapMarker',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Every style',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_map_markers
                        .customMapMarkerMatrix,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_map_markers
                        .customMapMarkerPlayground,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'HorizontalTripPlanner',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Planning a trip',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_map_map_chrome
                        .horizontalTripPlannerPlanning,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'MapControls',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Over the map',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_map_map_chrome
                        .mapControlsOverMap,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'MapSettingsButton',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Over the map (tap to open)',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_map_map_chrome
                        .mapSettingsButtonOverMap,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'MapSettingsModal',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Inline',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_map_map_chrome
                        .mapSettingsModalInline,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'PersonMapMarker',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Sample people (tap one)',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_map_markers
                        .personMapMarkerRoster,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'StationBottomSheet',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_map_map_sheets
                        .stationBottomSheetDefault,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'UnifiedClusterModal',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Cluster contents',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_map_map_sheets
                        .unifiedClusterModalContents,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'people',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'PersonCard',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_people_pulse
                        .personCardDefault,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Grid',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_people_pulse
                        .personCardGrid,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'pulse',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'ContactRosterTile',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_people_pulse
                        .contactRosterTileDefault,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Every recency level',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_people_pulse
                        .contactRosterTileLevels,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'LogContactSheet',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'As shown (tap to open)',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_people_pulse
                        .logContactSheetShown,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Inline',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_people_pulse
                        .logContactSheetInline,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'PulseCalendar',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Interactive',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_people_pulse
                        .pulseCalendarInteractive,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'shared',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'AmbientField',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Full bleed',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_motion
                        .ambientFieldFullBleed,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'AmbientScaffold',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'With header',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_motion
                        .ambientScaffoldWithHeader,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'ChromaticPulse',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_motion
                        .chromaticPulsePlayground,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'CustomTextFormField',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_inputs
                        .customTextFormFieldPlayground,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Validation error',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_inputs
                        .customTextFormFieldError,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'GlassContainer',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Grouped panels',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_container
                        .glassContainerGrouped,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Isolated (over other glass)',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_container
                        .glassContainerIsolated,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_container
                        .glassContainerPlayground,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'GlassDialog',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Confirm (tap to open)',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_surfaces
                        .glassDialogConfirm,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Panel (tap to open)',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_surfaces
                        .glassDialogPanel,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_surfaces
                        .glassDialogPlayground,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'GlassEmptyState',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Error',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_empty_state
                        .glassEmptyStateError,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_empty_state
                        .glassEmptyStatePlayground,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'GlassHeader',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Long title',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_header
                        .glassHeaderLongTitle,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_header
                        .glassHeaderPlayground,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'GlassInlay',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_inlay
                        .glassInlayPlayground,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Variants',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_inlay
                        .glassInlayVariants,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'GlassSheet',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Action sheet (tap to open)',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_surfaces
                        .glassSheetActions,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Inline',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_surfaces
                        .glassSheetInline,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'GlassToast',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Tones (tap to show)',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_glass_surfaces
                        .glassToastTones,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'ImageEditorModal',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Profile picture',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_inputs
                        .imageEditorModalProfile,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'NavLabel',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'In a rail slot',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_inputs
                        .navLabelInSlot,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'NearbyAirportsSection',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'States',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_nearby
                        .nearbyAirportsStates,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'NearbyStationsSection',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'States',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_nearby
                        .nearbyStationsStates,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'PulseIndicator',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Inline in a row',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_motion
                        .pulseIndicatorInline,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_motion
                        .pulseIndicatorPlayground,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'ThermalButton',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_thermal
                        .thermalButtonPlayground,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Tones and states',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_thermal
                        .thermalButtonMatrix,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'ThermalResponse',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _map_my_friends_widgetbook_use_cases_components_shared_thermal
                        .thermalResponsePlayground,
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  _widgetbook.WidgetbookCategory(
    name: 'Screens',
    children: [
      _widgetbook.WidgetbookFolder(
        name: 'auth',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'ForgotPasswordScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder: _map_my_friends_widgetbook_use_cases_screens_auth
                    .forgotPasswordScreenDefault,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'LoginScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder: _map_my_friends_widgetbook_use_cases_screens_auth
                    .loginScreenDefault,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'RegisterScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder: _map_my_friends_widgetbook_use_cases_screens_auth
                    .registerScreenDefault,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'map',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'MapScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder: _map_my_friends_widgetbook_use_cases_screens_tabs
                    .mapScreenDefault,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'people',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'AddEditPersonScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Add',
                builder: _map_my_friends_widgetbook_use_cases_screens_pushed
                    .addPersonScreen,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Edit',
                builder: _map_my_friends_widgetbook_use_cases_screens_pushed
                    .editPersonScreen,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'PeopleScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'States',
                builder: _map_my_friends_widgetbook_use_cases_screens_tabs
                    .peopleScreenStates,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'PersonDetailsScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder: _map_my_friends_widgetbook_use_cases_screens_pushed
                    .personDetailsScreenDefault,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'profile',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'MeScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'States',
                builder: _map_my_friends_widgetbook_use_cases_screens_tabs
                    .meScreenStates,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'pulse',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'PulseScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'States',
                builder: _map_my_friends_widgetbook_use_cases_screens_tabs
                    .pulseScreenStates,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'settings',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'SettingsScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Location permission',
                builder: _map_my_friends_widgetbook_use_cases_screens_pushed
                    .settingsScreenLocation,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'shell',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'AuthWrapper',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Auth gate',
                builder: _map_my_friends_widgetbook_use_cases_screens_shell
                    .authWrapperGate,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'MainScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Navigation chrome',
                builder: _map_my_friends_widgetbook_use_cases_screens_shell
                    .mainScreenShell,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'trips',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'TripDetailsScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder: _map_my_friends_widgetbook_use_cases_screens_pushed
                    .tripDetailsScreenDefault,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'TripsScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'States',
                builder: _map_my_friends_widgetbook_use_cases_screens_tabs
                    .tripsScreenStates,
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];
