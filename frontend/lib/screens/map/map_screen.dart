import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../bloc/location/location_bloc.dart';
import '../../bloc/people/people_bloc.dart';
import '../../bloc/map/map_settings_cubit.dart';
import '../../components/map/map_controls.dart';
import '../../components/map/map_settings_button.dart';
import '../../components/map/person_map_marker.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

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
    return BlocProvider(
      create: (context) => MapSettingsCubit(),
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

                if (peopleState is PeopleLoaded) {
                  markers.addAll(
                    peopleState.people
                        .where((p) => p.latitude != null && p.longitude != null)
                        .map(
                          (p) => Marker(
                            point: LatLng(p.latitude!, p.longitude!),
                            width: 40,
                            height: 40,
                            child: PersonMapMarker(person: p),
                          ),
                        ),
                  );
                }

                return BlocBuilder<MapSettingsCubit, MapSettingsState>(
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
                            MarkerLayer(markers: markers),
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
                          MapControls(mapController: _mapController),
                        const MapSettingsButton(),
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
