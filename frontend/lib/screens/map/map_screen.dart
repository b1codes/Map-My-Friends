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
    if (settings.mapType == MapType.satellite) {
      return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }

    if (settings.mapType == MapType.minimal) {
      return _getMinimalMapUrl(context, settings);
    }

    // Standard mode (OpenStreetMap)
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'de') {
      return 'https://{s}.tile.openstreetmap.de/tiles/osmde/{z}/{x}/{y}.png';
    } else if (locale == 'fr') {
      return 'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png';
    }

    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  String _getMinimalMapUrl(BuildContext context, MapSettingsState settings) {
    ThemeMode mode = settings.themeMode;
    Brightness brightness;

    if (mode == ThemeMode.system) {
      brightness = Theme.of(context).brightness;
    } else if (mode == ThemeMode.light) {
      brightness = Brightness.light;
    } else {
      brightness = Brightness.dark;
    }

    if (brightness == Brightness.dark) {
      return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
    } else {
      return 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
    }
  }

  bool _isDark(BuildContext context, MapSettingsState settings) {
    if (settings.themeMode == ThemeMode.system) {
      return Theme.of(context).brightness == Brightness.dark;
    }
    return settings.themeMode == ThemeMode.dark;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LocalMapSettingsCubit>(
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
                    LatLng(state.position!.latitude, state.position!.longitude),
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
                final bounds = LatLngBounds.fromPoints(
                  state.stops.map((s) => s.location).toList(),
                );
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(50),
                  ),
                );
              },
            ),
          ],
          child: BlocBuilder<LocationBloc, LocationState>(
            builder: (context, locationState) {
              if (locationState is LocationLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              LatLng center = const LatLng(37.7749, -122.4194); // Default SF
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
                        final profileState = context.watch<ProfileBloc>().state;

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
                                pinColorHex: profileState.pinColor ?? '#2196F3',
                                pinStyle: profileState.pinStyle ?? 'teardrop',
                                pinIconType: profileState.pinIconType ?? 'none',
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
                                color: Colors.blue,
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
                                  key: ValueKey('airport_${airport.iataCode}'),
                                  point: LatLng(
                                    airport.latitude,
                                    airport.longitude,
                                  ),
                                  width: 28,
                                  height: 28,
                                  child: _MarkerIcon(
                                    icon: Icons.flight,
                                    color: const Color(0xFF1565C0),
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
                                Color color = const Color(0xFFE65100); // Orange

                                switch (station.stationType) {
                                  case 'major_station':
                                    iconData = Icons.train;
                                    color = const Color(0xFFE65100);
                                    break;
                                  case 'commuter_rail_station':
                                    iconData = Icons.directions_railway;
                                    color = const Color(0xFF00695C); // Teal 800
                                    break;
                                  case 'subway_station':
                                    iconData = Icons.subway;
                                    color = const Color(0xFF2E7D32); // Green 800
                                    break;
                                  case 'regional_station':
                                    iconData = Icons.train;
                                    color = const Color(0xFF607D8B); // Blue Grey
                                    break;
                                  default:
                                    iconData = Icons.train;
                                    color = const Color(0xFFE65100);
                                }

                                return Marker(
                                  key: ValueKey('station_${station.osmId}'),
                                  point: LatLng(
                                    station.latitude,
                                    station.longitude,
                                  ),
                                  width: 28,
                                  height: 28,
                                  child: _MarkerIcon(
                                    icon: iconData,
                                    color: color,
                                  ),
                                );
                              })
                              .toList(),
                        );
                      }

                      return BlocBuilder<TripBloc, TripState>(
                        builder: (context, tripState) {
                          final isTripPlanning = tripState.stops.isNotEmpty;

                          return Stack(
                            children: [
                              FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: center,
                                  initialZoom: 13.0,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        _getTileUrl(context, settingsState),
                                    subdomains: const ['a', 'b', 'c'],
                                    userAgentPackageName: 'com.mapmyfriends.app',
                                    tileProvider: kIsWeb
                                        ? NetworkTileProvider()
                                        : FMTCTileProvider(
                                            stores: const {
                                              'mapStore': BrowseStoreStrategy
                                                  .readUpdateCreate,
                                            },
                                          ),
                                    tileBuilder: (context, widget, tile) {
                                      bool isStandard = settingsState.mapType ==
                                          MapType.standard;
                                      bool isDark =
                                          _isDark(context, settingsState);

                                      if (isStandard && isDark) {
                                        return ColorFiltered(
                                          colorFilter: const ColorFilter.matrix(
                                            <double>[
                                              -1, 0, 0, 0, 255,
                                              0, -1, 0, 0, 255,
                                              0, 0, -1, 0, 255,
                                              0, 0, 0, 1, 0,
                                            ],
                                          ),
                                          child: widget,
                                        );
                                      }
                                      return widget;
                                    },
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
                                            color: Colors.indigo.withValues(
                                              alpha: 0.7,
                                            ),
                                            strokeWidth: 5,
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
                                      onMarkerTap: (marker) {
                                        final key = marker.key;
                                        if (key is ValueKey<String>) {
                                          final keyValue = key.value;
                                          if (keyValue.startsWith('person_')) {
                                            final id = keyValue.substring(7);
                                            if (peopleState is PeopleLoaded) {
                                              try {
                                                final person = peopleState
                                                    .people
                                                    .firstWhere(
                                                        (p) => p.id == id);
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
                                          } else if (keyValue
                                              .startsWith('airport_')) {
                                            final iata = keyValue.substring(8);
                                            if (airportState
                                                is MapAirportsLoaded) {
                                              try {
                                                final airport = airportState
                                                    .airports
                                                    .firstWhere((a) =>
                                                        a.iataCode == iata);
                                                showModalBottomSheet(
                                                  context: context,
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  builder: (context) =>
                                                      AirportBottomSheet(
                                                          airport: airport),
                                                );
                                              } catch (_) {}
                                            }
                                          } else if (keyValue
                                              .startsWith('station_')) {
                                            final osmId = int.tryParse(
                                                keyValue.substring(8));
                                            if (stationState
                                                is MapStationsLoaded) {
                                              try {
                                                final station = stationState
                                                    .stations
                                                    .firstWhere((s) =>
                                                        s.osmId == osmId);
                                                showModalBottomSheet(
                                                  context: context,
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  builder: (context) =>
                                                      StationBottomSheet(
                                                          station: station),
                                                );
                                              } catch (_) {}
                                            }
                                          }
                                        }
                                      },
                                      onClusterTap: (clusterNode) {
                                        List<dynamic> clusterItems = [];
                                        for (var marker in clusterNode.markers) {
                                          if (marker.key is ValueKey<String>) {
                                            final key =
                                                (marker.key as ValueKey<String>)
                                                    .value;
                                            if (key.startsWith('person_')) {
                                              final id = key.substring(7);
                                              if (peopleState is PeopleLoaded) {
                                                try {
                                                  clusterItems.add(
                                                    peopleState.people
                                                        .firstWhere(
                                                      (p) => p.id == id,
                                                    ),
                                                  );
                                                } catch (_) {}
                                              }
                                            } else if (key
                                                .startsWith('airport_')) {
                                              final iata = key.substring(8);
                                              if (airportState
                                                  is MapAirportsLoaded) {
                                                try {
                                                  clusterItems.add(
                                                    airportState.airports
                                                        .firstWhere(
                                                      (a) => a.iataCode == iata,
                                                    ),
                                                  );
                                                } catch (_) {}
                                              }
                                            } else if (key
                                                .startsWith('station_')) {
                                              final osmIdString =
                                                  key.substring(8);
                                              final osmId = int.tryParse(
                                                osmIdString,
                                              );
                                              if (stationState
                                                  is MapStationsLoaded) {
                                                try {
                                                  clusterItems.add(
                                                    stationState.stations
                                                        .firstWhere(
                                                      (s) => s.osmId == osmId,
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
                                            backgroundColor: Colors.transparent,
                                            builder: (context) =>
                                                UnifiedClusterModal(
                                              items: clusterItems,
                                              onZoom: () {
                                                Navigator.pop(context);
                                                _mapController.fitCamera(
                                                  CameraFit.bounds(
                                                    bounds: clusterNode.bounds,
                                                    padding: const EdgeInsets.all(50),
                                                  ),
                                                );
                                              },
                                            ),
                                          );
                                        }
                                      },
                                      builder: (context, clusterMarkers) {
                                        List<Widget> children = [];
                                        int displayCount =
                                            clusterMarkers.length > 4
                                                ? 3
                                                : clusterMarkers.length;
                                        bool hasExtra =
                                            clusterMarkers.length > 4;
                                        double itemSize = 36.0;
                                        double overlap = 20.0;
                                        double totalWidth = 0;
                                        if (displayCount > 0) {
                                          totalWidth =
                                              (displayCount - 1) * overlap +
                                                  itemSize;
                                          if (hasExtra) totalWidth += overlap;
                                        }
                                        for (int i = 0; i < displayCount; i++) {
                                          children.add(
                                            Positioned(
                                              left: i * overlap,
                                              child: SizedBox(
                                                width: itemSize,
                                                height: itemSize,
                                                child: clusterMarkers[i].child,
                                              ),
                                            ),
                                          );
                                        }
                                        if (hasExtra) {
                                          int extraCount =
                                              clusterMarkers.length - 3;
                                          children.add(
                                            Positioned(
                                              left: displayCount * overlap,
                                              child: Container(
                                                width: itemSize,
                                                height: itemSize,
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    width: 2,
                                                  ),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Colors.black26,
                                                      blurRadius: 4,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  '+$extraCount',
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onPrimaryContainer,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                        return Center(
                                          child: Container(
                                            width: totalWidth + 8,
                                            height: itemSize + 8,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .cardColor
                                                  .withValues(alpha: 0.8),
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Colors.black26,
                                                  blurRadius: 4,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Positioned(
                                                  left: 4,
                                                  top: 4,
                                                  width: totalWidth,
                                                  height: itemSize,
                                                  child: IgnorePointer(
                                                    child: Stack(
                                                      clipBehavior: Clip.none,
                                                      children: children,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  BlocBuilder<TripBloc, TripState>(
                                    builder: (context, state) {
                                      return MarkerLayer(
                                        markers: state.stops
                                            .asMap()
                                            .entries
                                            .map((entry) {
                                          final idx = entry.key;
                                          final stop = entry.value;
                                          final hasPeople = stop.people.isNotEmpty;
                                          final isAirport = stop.airport != null;
                                          final isStation = stop.station != null;
                                          final isPersonOnly = hasPeople && !isAirport && !isStation;

                                          Color color = Colors.indigo;
                                          if (isPersonOnly) {
                                            color = Colors.amber;
                                          } else if (isAirport) {
                                            color = const Color(0xFF1565C0);
                                          } else if (isStation) {
                                            color = const Color(0xFFE65100);
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
                                                  decoration: BoxDecoration(
                                                    color: color,
                                                    shape: BoxShape.circle,
                                                    border: isPersonOnly
                                                        ? Border.all(
                                                            color: Colors.white,
                                                            width: 2,
                                                          )
                                                        : null,
                                                    boxShadow: const [
                                                      BoxShadow(
                                                        color: Colors.black26,
                                                        blurRadius: 4,
                                                        offset: Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Center(
                                                    child: isAirport
                                                        ? const Icon(Icons.flight,
                                                            color: Colors.white,
                                                            size: 16)
                                                        : isStation
                                                            ? const Icon(
                                                                Icons.train,
                                                                color: Colors.white,
                                                                size: 16)
                                                            : Text(
                                                                String.fromCharCode(
                                                                    65 + idx),
                                                                style: TextStyle(
                                                                  color: isPersonOnly
                                                                      ? Colors.black87
                                                                      : Colors.white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: isPersonOnly
                                                                      ? 12
                                                                      : 14,
                                                                ),
                                                              ),
                                                  ),
                                                ),
                                                if (hasPeople && (isAirport || isStation))
                                                  Positioned(
                                                    right: -4,
                                                    top: -4,
                                                    child: Container(
                                                      padding: const EdgeInsets.all(4),
                                                      decoration: const BoxDecoration(
                                                        color: Colors.amber,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Text(
                                                        stop.people.length.toString(),
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.black87,
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

                                  RichAttributionWidget(
                                    alignment: AttributionAlignment.bottomLeft,
                                    attributions: [
                                      TextSourceAttribution(
                                        'OpenStreetMap contributors',
                                        onTap: () => launchUrl(
                                          Uri.parse(
                                            'https://openstreetmap.org/copyright',
                                          ),
                                        ),
                                      ),
                                    ],
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
                                top: MediaQuery.of(context).padding.top + 95,
                                right: 20,
                                child: _CompassIndicator(
                                  mapController: _mapController,
                                  onReset: _resetNorth,
                                ),
                              ),
                              const HorizontalTripPlanner(),
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
    );
  }
}

class _MarkerIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MarkerIcon({required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
        ],
        border: Border.all(color: color, width: 1.5),
      ),
      child: Center(child: Icon(icon, color: color, size: 16)),
    );
  }
}

class _CompassIndicator extends StatelessWidget {
  final MapController mapController;
  final VoidCallback onReset;
  const _CompassIndicator({required this.mapController, required this.onReset});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MapEvent>(
      stream: mapController.mapEventStream,
      builder: (context, snapshot) {
        final rotation = mapController.camera.rotation;
        if (rotation == 0) return const SizedBox.shrink();
        return GestureDetector(
          onTap: onReset,
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
                  Positioned(
                    top: 6,
                    child: CustomPaint(
                      size: const Size(10, 10),
                      painter: _NorthTrianglePainter(color: Colors.red),
                    ),
                  ),
                  Positioned(
                    bottom: 6,
                    child: Transform.rotate(
                      angle: math.pi,
                      child: CustomPaint(
                        size: const Size(10, 10),
                        painter: _NorthTrianglePainter(color: Colors.white70),
                      ),
                    ),
                  ),
                  const Text(
                    'N',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                      height: 1,
                    ),
                  ),
                ],
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
  _NorthTrianglePainter({required this.color});
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
