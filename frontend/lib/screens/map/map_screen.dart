import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../bloc/location/location_bloc.dart';
import '../../bloc/people/people_bloc.dart';
import '../../bloc/map/map_settings_cubit.dart';
import '../../bloc/map/local_map_settings_cubit.dart';
import '../../components/map/map_controls.dart';
import '../../components/map/map_settings_button.dart';
import '../../components/map/person_map_marker.dart';
import '../../components/map/custom_map_marker.dart';
import '../../components/map/unified_cluster_modal.dart';
import '../../components/shared/glass_container.dart';
import '../../components/map/map_bottom_sheets.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/profile/profile_state.dart';
import '../../bloc/airport/airport_bloc.dart';
import '../../bloc/airport/airport_state.dart';
import '../../bloc/station/station_bloc.dart';
import '../../bloc/station/station_state.dart';
import '../../bloc/trip/trip_bloc.dart';
import '../../bloc/trip/trip_state.dart';
import '../../components/map/horizontal_trip_planner.dart';
import '../../components/shared/thermal_response.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/window_size.dart';
import '../../components/shared/chromatic_pulse.dart';

// Spatial tokens per DESIGN.md §5: floating chrome lives at 20px inset; the
// compass clears the settings button (~75px tall plus its inset) with a
// spacing.lg gap.
const double _kChromeInset = 16.0;
const double _kCompassTopOffset = 72.0;
const double _kCameraFitPadding = 50.0;
const double _kFallbackLat = 37.7749;
const double _kFallbackLon = -122.4194;
const double _kInitialZoom = 13.0;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  void _resetNorth() {
    _mapController.rotate(0);
  }

  String _getTileUrl(BuildContext context, MapSettingsState settings) {
    final isDark = _isDark(context, settings);

    if (settings.mapType == MapType.satellite) {
      return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }

    if (settings.mapType == MapType.minimal) {
      return isDark
          ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
          : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
    }

    // Standard mode
    if (isDark) {
      return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
    }

    // Standard mode (OpenStreetMap) - Light
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'de') {
      return 'https://{s}.tile.openstreetmap.de/tiles/osmde/{z}/{x}/{y}.png';
    } else if (locale == 'fr') {
      return 'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png';
    }

    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  bool _isDark(BuildContext context, MapSettingsState settings) {
    if (settings.themeMode == ThemeMode.system) {
      return Theme.of(context).brightness == Brightness.dark;
    }
    return settings.themeMode == ThemeMode.dark;
  }

  @override
  Widget build(BuildContext context) {
    // The map carries the app's densest glass chrome — pan and zoom stacks, the
    // settings button, the compass, the trip planner, the locating pill, and one
    // pill per marker cluster. They share a single backdrop sample, so all of it
    // costs one BackdropFilter layer; the shell's nav bar owns the second, which
    // is the whole budget impeller-optimization.md allows.
    //
    // The group lives here rather than only in the shell so the screen is
    // self-contained: it renders correctly wherever it is mounted, including in
    // widget tests that pump it directly.
    return BackdropGroup(
      child: BlocProvider<LocalMapSettingsCubit>(
        create: (context) => LocalMapSettingsCubit(
          initialState: context.read<MapSettingsCubit>().state,
        ),
        child: Scaffold(
          body: MultiBlocListener(
            listeners: [
              BlocListener<LocationBloc, LocationState>(
                listener: (context, state) {
                  if (state is LocationLoaded && state.position != null) {
                    _mapController.move(
                      LatLng(
                        state.position!.latitude,
                        state.position!.longitude,
                      ),
                      13.0,
                    );
                  }
                },
              ),
              BlocListener<TripBloc, TripState>(
                listenWhen: (previous, current) =>
                    previous.stops != current.stops &&
                    current.stops.isNotEmpty &&
                    !current.isOptimizing,
                listener: (context, state) {
                  if (state.stops.length == 1) {
                    _mapController.move(
                      state.stops.first.location,
                      _kInitialZoom,
                    );
                  } else {
                    final bounds = LatLngBounds.fromPoints(
                      state.stops.map((s) => s.location).toList(),
                    );
                    _mapController.fitCamera(
                      CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(_kCameraFitPadding),
                      ),
                    );
                  }
                },
              ),
            ],
            child: BlocBuilder<LocationBloc, LocationState>(
              builder: (context, locationState) {
                // The map always renders — even while we're acquiring location.
                // A blank scaffold with a centered spinner would say "this is a
                // dashboard"; the Lit Window posture is that the map IS the
                // canvas. We just nudge it to a default coordinate and overlay
                // a calm pill telling the user what's happening.
                final isLocating = locationState is LocationLoading;
                LatLng center = const LatLng(_kFallbackLat, _kFallbackLon);
                if (locationState is LocationLoaded &&
                    locationState.position != null) {
                  center = LatLng(
                    locationState.position!.latitude,
                    locationState.position!.longitude,
                  );
                }

                return BlocBuilder<PeopleBloc, PeopleState>(
                  builder: (context, peopleState) {
                    final airportState = context.watch<AirportBloc>().state;
                    final stationState = context.watch<StationBloc>().state;

                    return BlocBuilder<LocalMapSettingsCubit, MapSettingsState>(
                      builder: (context, settingsState) {
                        List<Marker> markers = [];
                        if (locationState is LocationLoaded &&
                            locationState.position != null) {
                          final profileState = context
                              .watch<ProfileBloc>()
                              .state;

                          if (profileState is ProfileLoaded &&
                              (profileState.pinColor != null ||
                                  profileState.pinStyle != null ||
                                  profileState.pinIconType != null)) {
                            String initials = '';
                            if (profileState.firstName != null &&
                                profileState.firstName!.isNotEmpty) {
                              initials += profileState.firstName![0];
                            }
                            if (profileState.lastName != null &&
                                profileState.lastName!.isNotEmpty) {
                              initials += profileState.lastName![0];
                            }

                            markers.add(
                              Marker(
                                point: center,
                                width: 40,
                                height: 40,
                                child: CustomMapMarker(
                                  pinColorHex:
                                      profileState.pinColor ?? '#3F51B5',
                                  pinStyle: profileState.pinStyle ?? 'teardrop',
                                  pinIconType:
                                      profileState.pinIconType ?? 'none',
                                  pinEmoji: profileState.pinEmoji,
                                  initials: initials,
                                  profileImageUrl: profileState.profileImageUrl,
                                ),
                              ),
                            );
                          } else {
                            markers.add(
                              Marker(
                                point: center,
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.my_location,
                                  color: MapPalette.defaultPin,
                                  size: 40,
                                ),
                              ),
                            );
                          }
                        }

                        if (peopleState is PeopleLoaded) {
                          markers.addAll(
                            peopleState.people
                                .where(
                                  (p) =>
                                      p.latitude != null && p.longitude != null,
                                )
                                .map(
                                  (p) => Marker(
                                    key: ValueKey('person_${p.id}'),
                                    point: LatLng(p.latitude!, p.longitude!),
                                    width: 40,
                                    height: 40,
                                    child: PersonMapMarker(
                                      person: p,
                                      onTap: () {
                                        showModalBottomSheet(
                                          context: context,
                                          backgroundColor: Colors.transparent,
                                          builder: (context) =>
                                              UnifiedClusterModal(items: [p]),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                          );
                        }

                        if (settingsState.showAirports &&
                            airportState is MapAirportsLoaded) {
                          markers.addAll(
                            airportState.airports
                                .where((airport) {
                                  switch (settingsState.airportFilter) {
                                    case AirportFilter.international:
                                      return airport.airportType ==
                                          'large_airport';
                                    case AirportFilter.regional:
                                      return airport.airportType ==
                                          'medium_airport';
                                    case AirportFilter.all:
                                      return true;
                                  }
                                })
                                .map(
                                  (airport) => Marker(
                                    key: ValueKey(
                                      'airport_${airport.iataCode}',
                                    ),
                                    point: LatLng(
                                      airport.latitude,
                                      airport.longitude,
                                    ),
                                    width: 28,
                                    height: 28,
                                    child: Semantics(
                                      label:
                                          'Airport: ${airport.name} (${airport.iataCode})',
                                      button: true,
                                      child: const _MarkerIcon(
                                        icon: Icons.flight,
                                        color: MapPalette.airport,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          );
                        }

                        if (settingsState.showStations &&
                            stationState is MapStationsLoaded) {
                          markers.addAll(
                            stationState.stations
                                .where((station) {
                                  switch (settingsState.stationFilter) {
                                    case StationFilter.major:
                                      return station.stationType ==
                                          'major_station';
                                    case StationFilter.commuter:
                                      return station.stationType ==
                                          'commuter_rail_station';
                                    case StationFilter.subway:
                                      return station.stationType ==
                                          'subway_station';
                                    case StationFilter.regional:
                                      return station.stationType ==
                                          'regional_station';
                                    case StationFilter.all:
                                      return true;
                                  }
                                })
                                .map((station) {
                                  IconData iconData = Icons.train;
                                  Color color = MapPalette.majorStation;

                                  switch (station.stationType) {
                                    case 'major_station':
                                      iconData = Icons.train;
                                      color = MapPalette.majorStation;
                                      break;
                                    case 'commuter_rail_station':
                                      iconData = Icons.directions_railway;
                                      color = MapPalette.commuterRail;
                                      break;
                                    case 'subway_station':
                                      iconData = Icons.subway;
                                      color = MapPalette.subway;
                                      break;
                                    case 'regional_station':
                                      iconData = Icons.train;
                                      color = MapPalette.regionalStation;
                                      break;
                                    default:
                                      iconData = Icons.train;
                                      color = MapPalette.majorStation;
                                  }

                                  return Marker(
                                    key: ValueKey('station_${station.osmId}'),
                                    point: LatLng(
                                      station.latitude,
                                      station.longitude,
                                    ),
                                    width: 28,
                                    height: 28,
                                    child: Semantics(
                                      label: 'Station: ${station.name}',
                                      button: true,
                                      child: _MarkerIcon(
                                        icon: iconData,
                                        color: color,
                                      ),
                                    ),
                                  );
                                })
                                .toList(),
                          );
                        }

                        return BlocBuilder<TripBloc, TripState>(
                          builder: (context, tripState) {
                            final isTripPlanning = tripState.stops.isNotEmpty;
                            final reduceMotion = MediaQuery.disableAnimationsOf(
                              context,
                            );
                            final routeColor = Theme.of(
                              context,
                            ).colorScheme.primary;

                            return Stack(
                              children: [
                                FlutterMap(
                                  mapController: _mapController,
                                  options: MapOptions(
                                    initialCenter: center,
                                    initialZoom: _kInitialZoom,
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: _getTileUrl(
                                        context,
                                        settingsState,
                                      ),
                                      subdomains: const ['a', 'b', 'c'],
                                      userAgentPackageName:
                                          'com.mapmyfriends.app',
                                      tileProvider: kIsWeb
                                          // Zooming prunes a screenful of
                                          // tiles at once, and this provider
                                          // aborts their in-flight requests by
                                          // default. On web the abort escapes
                                          // package:http's browser client as
                                          // an uncaught DOMException on every
                                          // zoom-out, ahead of flutter_map's
                                          // own silent handling of it.
                                          //
                                          // Removing the cause is the only
                                          // reliable fix: with no abort
                                          // trigger there is no AbortError to
                                          // intercept. The cost is that
                                          // obsolete tile requests run to
                                          // completion on a fast zoom.
                                          ? NetworkTileProvider(
                                              abortObsoleteRequests: false,
                                            )
                                          : FMTCTileProvider(
                                              stores: const {
                                                'mapStore': BrowseStoreStrategy
                                                    .readUpdateCreate,
                                              },
                                            ),
                                    ),
                                    BlocBuilder<TripBloc, TripState>(
                                      builder: (context, state) {
                                        if (state.routePoints.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        return PolylineLayer(
                                          polylines: [
                                            Polyline(
                                              points: state.routePoints,
                                              color: routeColor,
                                              strokeWidth: 3,
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    MarkerClusterLayerWidget(
                                      options: MarkerClusterLayerOptions(
                                        maxClusterRadius: 45,
                                        size: const Size(120, 48),
                                        markers: markers,
                                        disableClusteringAtZoom: 19,
                                        spiderfyCluster: false,
                                        zoomToBoundsOnClick: false,
                                        animationsOptions: reduceMotion
                                            ? const AnimationsOptions(
                                                zoom: Duration.zero,
                                                fitBound: Duration.zero,
                                                centerMarker: Duration.zero,
                                                spiderfy: Duration.zero,
                                              )
                                            : const AnimationsOptions(),
                                        onMarkerTap: (marker) {
                                          final key = marker.key;
                                          if (key is ValueKey<String>) {
                                            final keyValue = key.value;
                                            if (keyValue.startsWith(
                                              'person_',
                                            )) {
                                              final id = keyValue.substring(7);
                                              if (peopleState is PeopleLoaded) {
                                                try {
                                                  final person = peopleState
                                                      .people
                                                      .firstWhere(
                                                        (p) => p.id == id,
                                                      );
                                                  showModalBottomSheet(
                                                    context: context,
                                                    backgroundColor:
                                                        Colors.transparent,
                                                    builder: (context) =>
                                                        UnifiedClusterModal(
                                                          items: [person],
                                                        ),
                                                  );
                                                } catch (_) {}
                                              }
                                            } else if (keyValue.startsWith(
                                              'airport_',
                                            )) {
                                              final iata = keyValue.substring(
                                                8,
                                              );
                                              if (airportState
                                                  is MapAirportsLoaded) {
                                                try {
                                                  final airport = airportState
                                                      .airports
                                                      .firstWhere(
                                                        (a) =>
                                                            a.iataCode == iata,
                                                      );
                                                  showModalBottomSheet(
                                                    context: context,
                                                    backgroundColor:
                                                        Colors.transparent,
                                                    builder: (context) =>
                                                        AirportBottomSheet(
                                                          airport: airport,
                                                        ),
                                                  );
                                                } catch (_) {}
                                              }
                                            } else if (keyValue.startsWith(
                                              'station_',
                                            )) {
                                              final osmId = int.tryParse(
                                                keyValue.substring(8),
                                              );
                                              if (stationState
                                                  is MapStationsLoaded) {
                                                try {
                                                  final station = stationState
                                                      .stations
                                                      .firstWhere(
                                                        (s) => s.osmId == osmId,
                                                      );
                                                  showModalBottomSheet(
                                                    context: context,
                                                    backgroundColor:
                                                        Colors.transparent,
                                                    builder: (context) =>
                                                        StationBottomSheet(
                                                          station: station,
                                                        ),
                                                  );
                                                } catch (_) {}
                                              }
                                            }
                                          }
                                        },
                                        onClusterTap: (clusterNode) {
                                          List<dynamic> clusterItems = [];
                                          for (var marker
                                              in clusterNode.markers) {
                                            if (marker.key
                                                is ValueKey<String>) {
                                              final key =
                                                  (marker.key
                                                          as ValueKey<String>)
                                                      .value;
                                              if (key.startsWith('person_')) {
                                                final id = key.substring(7);
                                                if (peopleState
                                                    is PeopleLoaded) {
                                                  try {
                                                    clusterItems.add(
                                                      peopleState.people
                                                          .firstWhere(
                                                            (p) => p.id == id,
                                                          ),
                                                    );
                                                  } catch (_) {}
                                                }
                                              } else if (key.startsWith(
                                                'airport_',
                                              )) {
                                                final iata = key.substring(8);
                                                if (airportState
                                                    is MapAirportsLoaded) {
                                                  try {
                                                    clusterItems.add(
                                                      airportState.airports
                                                          .firstWhere(
                                                            (a) =>
                                                                a.iataCode ==
                                                                iata,
                                                          ),
                                                    );
                                                  } catch (_) {}
                                                }
                                              } else if (key.startsWith(
                                                'station_',
                                              )) {
                                                final osmIdString = key
                                                    .substring(8);
                                                final osmId = int.tryParse(
                                                  osmIdString,
                                                );
                                                if (stationState
                                                    is MapStationsLoaded) {
                                                  try {
                                                    clusterItems.add(
                                                      stationState.stations
                                                          .firstWhere(
                                                            (s) =>
                                                                s.osmId ==
                                                                osmId,
                                                          ),
                                                    );
                                                  } catch (_) {}
                                                }
                                              }
                                            }
                                          }

                                          if (clusterItems.isNotEmpty) {
                                            showModalBottomSheet(
                                              context: context,
                                              backgroundColor:
                                                  Colors.transparent,
                                              builder: (context) =>
                                                  UnifiedClusterModal(
                                                    items: clusterItems,
                                                    onZoom: () {
                                                      Navigator.pop(context);
                                                      _mapController.fitCamera(
                                                        CameraFit.bounds(
                                                          bounds: clusterNode
                                                              .bounds,
                                                          padding:
                                                              const EdgeInsets.all(
                                                                50,
                                                              ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                            );
                                          }
                                        },
                                        builder: (context, clusterMarkers) {
                                          // Lit Window cluster preview: a glass
                                          // pill (high-contrast-aware via
                                          // GlassContainer) wrapping an overlapping
                                          // avatar stack, with a "+N" tile in
                                          // Evening Indigo Tint for overflow.
                                          // Flat-By-Default: no resting shadow on
                                          // either the pill or the +N tile.
                                          final scheme = Theme.of(
                                            context,
                                          ).colorScheme;
                                          final List<Widget> children = [];
                                          final int displayCount =
                                              clusterMarkers.length > 4
                                              ? 3
                                              : clusterMarkers.length;
                                          final bool hasExtra =
                                              clusterMarkers.length > 4;
                                          const double itemSize = 36.0;
                                          const double overlap = 20.0;
                                          double totalWidth = 0;
                                          if (displayCount > 0) {
                                            totalWidth =
                                                (displayCount - 1) * overlap +
                                                itemSize;
                                            if (hasExtra) totalWidth += overlap;
                                          }
                                          for (
                                            int i = 0;
                                            i < displayCount;
                                            i++
                                          ) {
                                            children.add(
                                              Positioned(
                                                left: i * overlap,
                                                child: SizedBox(
                                                  width: itemSize,
                                                  height: itemSize,
                                                  child:
                                                      clusterMarkers[i].child,
                                                ),
                                              ),
                                            );
                                          }
                                          if (hasExtra) {
                                            final extraCount =
                                                clusterMarkers.length - 3;
                                            children.add(
                                              Positioned(
                                                left: displayCount * overlap,
                                                child: Container(
                                                  width: itemSize,
                                                  height: itemSize,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        scheme.primaryContainer,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: scheme.primary,
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    '+$extraCount',
                                                    style: TextStyle(
                                                      color: scheme
                                                          .onPrimaryContainer,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 12,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                          return Center(
                                            child: ThermalResponse(
                                              borderRadius: MapGlass.radiusLg,
                                              child: GlassContainer(
                                                borderRadius:
                                                    MapGlass.radiusLg, // pill
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                child: SizedBox(
                                                  width: totalWidth,
                                                  height: itemSize,
                                                  child: IgnorePointer(
                                                    child: Stack(
                                                      clipBehavior: Clip.none,
                                                      children: children,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    BlocBuilder<TripBloc, TripState>(
                                      builder: (context, state) {
                                        // Trip stops live in the rare Aurora
                                        // Pink slot per DESIGN.md §2: pink is
                                        // reserved for "a trip happening this
                                        // week" — these markers literally ARE
                                        // that surface. Airport/station stops
                                        // keep their category accents so a
                                        // trip with mixed stops still reads as
                                        // a sequence at a glance.
                                        final scheme = Theme.of(
                                          context,
                                        ).colorScheme;
                                        return MarkerLayer(
                                          markers: state.stops.asMap().entries.map((
                                            entry,
                                          ) {
                                            final idx = entry.key;
                                            final stop = entry.value;
                                            final hasPeople =
                                                stop.people.isNotEmpty;
                                            final isAirport =
                                                stop.airport != null;
                                            final isStation =
                                                stop.station != null;
                                            final isPersonOnly =
                                                hasPeople &&
                                                !isAirport &&
                                                !isStation;

                                            Color color = scheme.primary;
                                            Color onColor = Colors.white;
                                            if (isPersonOnly) {
                                              color = scheme.secondary;
                                              onColor = scheme.onSecondary;
                                            } else if (isAirport) {
                                              color = MapPalette.airport;
                                            } else if (isStation) {
                                              color = MapPalette.majorStation;
                                            }

                                            return Marker(
                                              point: stop.location,
                                              width: isPersonOnly ? 24 : 30,
                                              height: isPersonOnly ? 24 : 30,
                                              alignment: isPersonOnly
                                                  ? Alignment.bottomLeft
                                                  : Alignment.center,
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  Container(
                                                    // Separation from the tile
                                                    // comes from a ring, not a
                                                    // cast shadow: DESIGN.md §4
                                                    // resolves depth by
                                                    // refraction and §6 bans
                                                    // drop shadows outright.
                                                    // The person-only marker
                                                    // already carried this
                                                    // ring; extending it to
                                                    // every stop makes the
                                                    // family read as one
                                                    // system and reads on both
                                                    // light and dark tiles.
                                                    decoration: BoxDecoration(
                                                      color: color,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.white,
                                                        width: 2,
                                                      ),
                                                    ),
                                                    child: Center(
                                                      child: isAirport
                                                          ? const Icon(
                                                              Icons.flight,
                                                              color:
                                                                  Colors.white,
                                                              size: 16,
                                                            )
                                                          : isStation
                                                          ? const Icon(
                                                              Icons.train,
                                                              color:
                                                                  Colors.white,
                                                              size: 16,
                                                            )
                                                          : Text(
                                                              String.fromCharCode(
                                                                65 + idx,
                                                              ),
                                                              style: TextStyle(
                                                                color: onColor,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize:
                                                                    isPersonOnly
                                                                    ? 12
                                                                    : 14,
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                  if (hasPeople &&
                                                      (isAirport || isStation))
                                                    Positioned(
                                                      right: -4,
                                                      top: -4,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              4,
                                                            ),
                                                        decoration:
                                                            BoxDecoration(
                                                              color: scheme
                                                                  .secondary,
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                        child: Text(
                                                          stop.people.length
                                                              .toString(),
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: scheme
                                                                .onSecondary,
                                                            fontFeatures: const [
                                                              FontFeature.tabularFigures(),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),

                                    // Tile attribution is a licence term, not
                                    // decoration, so it has to clear the
                                    // floating navigation rather than sit
                                    // behind its glass. RichAttributionWidget
                                    // aligns itself internally, so the offset
                                    // has to come from outside it.
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: MapWindow.of(
                                          context,
                                        ).navBarInset,
                                      ),
                                      child: RichAttributionWidget(
                                        alignment:
                                            AttributionAlignment.bottomLeft,
                                        attributions: [
                                          TextSourceAttribution(
                                            'OpenStreetMap contributors',
                                            onTap: () => launchUrl(
                                              Uri.parse(
                                                'https://openstreetmap.org/copyright',
                                              ),
                                            ),
                                          ),
                                          if (settingsState.mapType ==
                                                  MapType.minimal ||
                                              _isDark(context, settingsState))
                                            TextSourceAttribution(
                                              '© CartoDB',
                                              onTap: () => launchUrl(
                                                Uri.parse(
                                                  'https://carto.com/attributions',
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (settingsState.showControls)
                                  MapControls(
                                    mapController: _mapController,
                                    isBottomModalVisible: isTripPlanning,
                                  ),
                                const MapSettingsButton(),
                                Positioned(
                                  top:
                                      MediaQuery.of(context).padding.top +
                                      _kCompassTopOffset,
                                  right: _kChromeInset,
                                  child: _CompassIndicator(
                                    mapController: _mapController,
                                    onReset: _resetNorth,
                                  ),
                                ),
                                const HorizontalTripPlanner(),
                                if (isLocating) const _LocatingPill(),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Calm, non-blocking status pill shown while we acquire the user's location.
/// Per DESIGN.md §1: the map stays the canvas; chrome defers to it. A full-
/// screen blocker would shift the register toward "dashboard waiting" —
/// exactly the SaaS-template energy PRODUCT.md anti-references.
class _LocatingPill extends StatelessWidget {
  const _LocatingPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: MediaQuery.of(context).padding.top + _kChromeInset,
      left: 0,
      right: 0,
      child: Center(
        child: GlassContainer(
          borderRadius: MapGlass.radiusLg, // pill
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          semanticLabel: AppLocalizations.of(context)!.mapFindingYou,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: ChromaticPulse(
                  colors: PulseIndicator.paletteOf(context),
                  borderRadius: 8,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)!.mapFindingYou,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact overlay marker (airport / station). Uses the theme surface as the
/// fill — never pure white, per the No-Pure-White-Surfaces Rule. The
/// category accent acts as the 1.5px border and icon color so the marker
/// shape (circle) plus the icon (flight / train / subway / directions_railway)
/// together carry meaning, satisfying the airport/station distinct-shape
/// requirement for colorblind readers. Resting shadow is intentional: these
/// genuinely float over the map (DESIGN.md §4 marker exception).
class _MarkerIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MarkerIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
      child: Center(child: Icon(icon, color: color, size: 14)),
    );
  }
}

class _CompassIndicator extends StatelessWidget {
  final MapController mapController;
  final VoidCallback onReset;
  const _CompassIndicator({required this.mapController, required this.onReset});

  @override
  Widget build(BuildContext context) {
    // North-arrow red is a deliberate exception to the Evening Palette: red
    // is the universally-read "north" convention on compasses, so it carries
    // more meaning than brand discipline here. Tokenized as
    // MapPalette.compassNorth so it's a named exception rather than a leak.
    final scheme = Theme.of(context).colorScheme;
    final southColor = scheme.onSurface.withValues(alpha: 0.5);

    return StreamBuilder<MapEvent>(
      stream: mapController.mapEventStream,
      builder: (context, snapshot) {
        final rotation = mapController.camera.rotation;
        if (rotation == 0) return const SizedBox.shrink();
        return Semantics(
          button: true,
          label: 'Reset compass to north',
          child: ThermalResponse(
            onTap: onReset,
            borderRadius: 22,
            child: GlassContainer(
              width: 44,
              height: 44,
              padding: EdgeInsets.zero,
              borderRadius: 22,
              child: Transform.rotate(
                angle: -rotation * (math.pi / 180),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned(
                      top: 6,
                      child: CustomPaint(
                        size: Size(10, 10),
                        painter: _NorthTrianglePainter(
                          color: MapPalette.compassNorth,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      child: Transform.rotate(
                        angle: math.pi,
                        child: CustomPaint(
                          size: const Size(10, 10),
                          painter: _NorthTrianglePainter(color: southColor),
                        ),
                      ),
                    ),
                    const Text(
                      'N',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: MapPalette.compassNorth,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NorthTrianglePainter extends CustomPainter {
  final Color color;
  const _NorthTrianglePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _NorthTrianglePainter oldDelegate) =>
      color != oldDelegate.color;
}
