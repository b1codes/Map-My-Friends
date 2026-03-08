import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
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
import '../../components/map/cluster_people_modal.dart';
import '../../components/shared/glass_container.dart';
import '../../models/person.dart';
import '../../models/airport.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/profile/profile_state.dart';
import '../../bloc/airport/airport_bloc.dart';
import '../../bloc/airport/airport_state.dart';

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
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  String _getMinimalMapUrl(BuildContext context, MapSettingsState settings) {
    ThemeMode mode = settings.themeMode;
    Brightness brightness;

    if (mode == ThemeMode.system) {
      // Use Theme.of(context).brightness to catch the app's current effective theme
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
        body: BlocConsumer<LocationBloc, LocationState>(
          listener: (context, state) {
            if (state is LocationLoaded && state.position != null) {
              _mapController.move(
                LatLng(state.position!.latitude, state.position!.longitude),
                13.0,
              );
            }
          },
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
                        .where((p) => p.latitude != null && p.longitude != null)
                        .map(
                          (p) => Marker(
                            key: ValueKey(p.id),
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
                                      ClusterPeopleModal.withPeople(
                                        people: [p],
                                      ),
                                );
                              },
                            ),
                          ),
                        ),
                  );
                }

                return BlocBuilder<LocalMapSettingsCubit, MapSettingsState>(
                  builder: (context, settingsState) {
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
                              urlTemplate: _getTileUrl(context, settingsState),
                              subdomains: const ['a', 'b', 'c'],
                              userAgentPackageName: 'com.mapmyfriends.app',
                              tileBuilder: (context, widget, tile) {
                                // Check if we are in Standard mode AND Dark mode
                                bool isStandard =
                                    settingsState.mapType == MapType.standard;
                                bool isDark = _isDark(context, settingsState);

                                if (isStandard && isDark) {
                                  return ColorFiltered(
                                    colorFilter: const ColorFilter.matrix(
                                      <double>[
                                        -1,
                                        0,
                                        0,
                                        0,
                                        255,
                                        0,
                                        -1,
                                        0,
                                        0,
                                        255,
                                        0,
                                        0,
                                        -1,
                                        0,
                                        255,
                                        0,
                                        0,
                                        0,
                                        1,
                                        0,
                                      ],
                                    ),
                                    child: widget,
                                  );
                                }
                                return widget;
                              },
                            ),
                            MarkerClusterLayerWidget(
                              options: MarkerClusterLayerOptions(
                                maxClusterRadius: 45,
                                size: const Size(120, 48),
                                markers: markers,
                                disableClusteringAtZoom: 19,
                                spiderfyCluster:
                                    false, // Turn off exploding pins out
                                onMarkerTap: (marker) {
                                  // Fallback tap handler if single marker tapped
                                  if (marker.key is ValueKey<String> &&
                                      peopleState is PeopleLoaded) {
                                    final id =
                                        (marker.key as ValueKey<String>).value;
                                    final person = peopleState.people
                                        .firstWhere((p) => p.id == id);
                                    showModalBottomSheet(
                                      context: context,
                                      backgroundColor: Colors.transparent,
                                      builder: (context) =>
                                          ClusterPeopleModal.withPeople(
                                            people: [person],
                                          ),
                                    );
                                  }
                                },
                                onClusterTap: (clusterNode) {
                                  if (peopleState is PeopleLoaded) {
                                    // Extract all Person objects belonging to the cluster
                                    List<Person> clusterPeople = [];
                                    for (var marker in clusterNode.markers) {
                                      if (marker.key is ValueKey<String>) {
                                        final id =
                                            (marker.key as ValueKey<String>)
                                                .value;
                                        try {
                                          clusterPeople.add(
                                            peopleState.people.firstWhere(
                                              (p) => p.id == id,
                                            ),
                                          );
                                        } catch (_) {}
                                      }
                                    }

                                    if (clusterPeople.isNotEmpty) {
                                      showModalBottomSheet(
                                        context: context,
                                        backgroundColor: Colors.transparent,
                                        builder: (context) =>
                                            ClusterPeopleModal.withPeople(
                                              people: clusterPeople,
                                            ),
                                      );
                                    }
                                  }
                                },
                                builder: (context, clusterMarkers) {
                                  List<Widget> children = [];

                                  int displayCount = clusterMarkers.length > 4
                                      ? 3
                                      : clusterMarkers.length;
                                  bool hasExtra = clusterMarkers.length > 4;

                                  double itemSize = 36.0;
                                  double overlap = 20.0; // Tightly overlap pins

                                  // Calculate total width of the overlapping group
                                  double totalWidth = 0;
                                  if (displayCount > 0) {
                                    totalWidth =
                                        (displayCount - 1) * overlap + itemSize;
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
                                    int extraCount = clusterMarkers.length - 3;
                                    children.add(
                                      Positioned(
                                        left: displayCount * overlap,
                                        child: Container(
                                          width: itemSize,
                                          height: itemSize,
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
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
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onPrimaryContainer,
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
                                      width:
                                          totalWidth +
                                          8, // 4px padding on each side
                                      height:
                                          itemSize +
                                          8, // 4px padding top/bottom
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).cardColor.withOpacity(0.8),
                                        borderRadius: BorderRadius.circular(24),
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
                            // Airport markers layer
                            if (settingsState.showAirports)
                              BlocBuilder<AirportBloc, AirportState>(
                                builder: (context, airportState) {
                                  if (airportState is MapAirportsLoaded) {
                                    return MarkerLayer(
                                      markers: airportState.airports
                                          .map(
                                            (airport) => Marker(
                                              point: LatLng(
                                                airport.latitude,
                                                airport.longitude,
                                              ),
                                              width: 28,
                                              height: 28,
                                              child: GestureDetector(
                                                onTap: () {
                                                  showModalBottomSheet(
                                                    context: context,
                                                    backgroundColor:
                                                        Colors.transparent,
                                                    builder: (context) =>
                                                        _AirportBottomSheet(
                                                          airport: airport,
                                                        ),
                                                  );
                                                },
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    shape: BoxShape.circle,
                                                    boxShadow: const [
                                                      BoxShadow(
                                                        color: Colors.black26,
                                                        blurRadius: 3,
                                                        offset: Offset(0, 1),
                                                      ),
                                                    ],
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFF1565C0,
                                                      ),
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons.flight,
                                                      color: Color(0xFF1565C0),
                                                      size: 16,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                          ],
                        ),
                        if (settingsState.showControls)
                          MapControls(mapController: _mapController),
                        const MapSettingsButton(),
                        // Compass indicator
                        StreamBuilder<MapEvent>(
                          stream: _mapController.mapEventStream,
                          builder: (context, snapshot) {
                            final rotation = _mapController.camera.rotation;
                            // Only show compass when map is rotated
                            if (rotation == 0) {
                              return const SizedBox.shrink();
                            }
                            return Positioned(
                              top: MediaQuery.of(context).padding.top + 95,
                              right: 20,
                              child: GestureDetector(
                                onTap: _resetNorth,
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
                                        // North indicator (red triangle)
                                        Positioned(
                                          top: 6,
                                          child: CustomPaint(
                                            size: const Size(10, 10),
                                            painter: _NorthTrianglePainter(
                                              color: Colors.red,
                                            ),
                                          ),
                                        ),
                                        // South indicator (white/grey triangle)
                                        Positioned(
                                          bottom: 6,
                                          child: Transform.rotate(
                                            angle: math.pi,
                                            child: CustomPaint(
                                              size: const Size(10, 10),
                                              painter: _NorthTrianglePainter(
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // "N" label
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
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
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
  bool shouldRepaint(covariant _NorthTrianglePainter oldDelegate) {
    return color != oldDelegate.color;
  }
}

class _AirportBottomSheet extends StatelessWidget {
  final Airport airport;

  const _AirportBottomSheet({required this.airport});

  @override
  Widget build(BuildContext context) {
    final typeLabel = airport.airportType == 'large_airport'
        ? 'International Airport'
        : 'Regional Airport';

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.flight,
                color: Color(0xFF1565C0),
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              airport.name,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              airport.iataCode,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF1565C0),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${airport.city}, ${airport.country}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              typeLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
