import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/map/map_settings_cubit.dart';
import '../../bloc/map/local_map_settings_cubit.dart';
import '../shared/glass_container.dart';

class MapSettingsModal extends StatelessWidget {
  const MapSettingsModal({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Map Settings',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            BlocBuilder<LocalMapSettingsCubit, MapSettingsState>(
              builder: (context, state) {
                return Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Show Map Controls'),
                      value: state.showControls,
                      onChanged: (value) {
                        context.read<LocalMapSettingsCubit>().toggleControls();
                      },
                      secondary: const Icon(Icons.control_camera),
                    ),
                    SwitchListTile(
                      title: const Text('Show Airports'),
                      value: state.showAirports,
                      onChanged: (value) {
                        context.read<LocalMapSettingsCubit>().toggleAirports();
                      },
                      secondary: const Icon(Icons.flight),
                    ),
                    if (state.showAirports) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 16.0,
                          right: 16.0,
                          bottom: 8.0,
                        ),
                        child: SegmentedButton<AirportFilter>(
                          segments: const [
                            ButtonSegment(
                              value: AirportFilter.international,
                              label: Text('International'),
                              icon: Icon(Icons.public, size: 16),
                            ),
                            ButtonSegment(
                              value: AirportFilter.all,
                              label: Text('Both'),
                            ),
                            ButtonSegment(
                              value: AirportFilter.regional,
                              label: Text('Regional'),
                              icon: Icon(Icons.location_city, size: 16),
                            ),
                          ],
                          selected: {state.airportFilter},
                          onSelectionChanged: (Set<AirportFilter> selection) {
                            context
                                .read<LocalMapSettingsCubit>()
                                .setAirportFilter(selection.first);
                          },
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            side: WidgetStateProperty.all(
                              BorderSide(
                                color: Colors.grey.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    SwitchListTile(
                      title: const Text('Show Train Stations'),
                      value: state.showStations,
                      onChanged: (value) {
                        context.read<LocalMapSettingsCubit>().toggleStations();
                      },
                      secondary: const Icon(Icons.train),
                    ),
                    if (state.showStations) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 16.0,
                          right: 16.0,
                          bottom: 8.0,
                        ),
                        child: SegmentedButton<StationFilter>(
                          segments: const [
                            ButtonSegment(
                              value: StationFilter.all,
                              label: Text('All'),
                            ),
                            ButtonSegment(
                              value: StationFilter.major,
                              label: Text('Amtrak'),
                              icon: Icon(Icons.train, size: 14),
                            ),
                            ButtonSegment(
                              value: StationFilter.commuter,
                              label: Text('Rail'),
                              icon: Icon(Icons.directions_railway, size: 14),
                            ),
                            ButtonSegment(
                              value: StationFilter.subway,
                              label: Text('Subway'),
                              icon: Icon(Icons.subway, size: 14),
                            ),
                            ButtonSegment(
                              value: StationFilter.regional,
                              label: Text('Other'),
                            ),
                          ],
                          selected: {state.stationFilter},
                          onSelectionChanged: (Set<StationFilter> selection) {
                            context
                                .read<LocalMapSettingsCubit>()
                                .setStationFilter(selection.first);
                          },
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            side: WidgetStateProperty.all(
                              BorderSide(
                                color: Colors.grey.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const Divider(),
                    const ListTile(title: Text('Distance Unit')),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: SegmentedButton<DistanceUnit>(
                        segments: const [
                          ButtonSegment(
                            value: DistanceUnit.metric,
                            label: Text('Metric (km)'),
                            icon: Icon(Icons.straighten),
                          ),
                          ButtonSegment(
                            value: DistanceUnit.imperial,
                            label: Text('Imperial (mi)'),
                            icon: Icon(Icons.architecture),
                          ),
                        ],
                        selected: {state.distanceUnit},
                        onSelectionChanged: (Set<DistanceUnit> newSelection) {
                          context.read<LocalMapSettingsCubit>().setDistanceUnit(
                            newSelection.first,
                          );
                        },
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: WidgetStateProperty.all(
                            BorderSide(
                              color: Colors.grey.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Map Type'),
                      trailing: DropdownButton<MapType>(
                        value: state.mapType,
                        onChanged: (MapType? newValue) {
                          if (newValue != null) {
                            context.read<LocalMapSettingsCubit>().setMapType(
                              newValue,
                            );
                          }
                        },
                        items: MapType.values.map((MapType type) {
                          return DropdownMenuItem<MapType>(
                            value: type,
                            child: Text(type.name.toUpperCase()),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(),
                    const ListTile(title: Text('Map Theme')),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto),
                            label: Text('Match App'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {state.themeMode},
                        onSelectionChanged: (Set<ThemeMode> newSelection) {
                          context.read<LocalMapSettingsCubit>().setMapTheme(
                            newSelection.first,
                          );
                        },
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: WidgetStateProperty.all(
                            BorderSide(
                              color: Colors.grey.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
