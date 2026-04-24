import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/location/location_bloc.dart';
import '../../bloc/theme/theme_cubit.dart';
import '../../bloc/map/map_settings_cubit.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocListener<LocationBloc, LocationState>(
        listener: (context, state) {
          if (state is LocationPermissionDenied) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission denied')),
            );
          } else if (state is LocationPermissionDeniedForever) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied forever'),
              ),
            );
          } else if (state is LocationLoaded) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Location loaded')));
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            Text(
              'Appearance',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            BlocBuilder<ThemeCubit, ThemeMode>(
              builder: (context, themeMode) {
                return SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (Set<ThemeMode> newSelection) {
                    context.read<ThemeCubit>().setTheme(newSelection.first);
                  },
                  showSelectedIcon: false,
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              'Default Map Settings',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            BlocBuilder<MapSettingsCubit, MapSettingsState>(
              builder: (context, state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Map Style',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<MapType>(
                      segments: const [
                        ButtonSegment(
                          value: MapType.standard,
                          icon: Icon(Icons.map),
                          label: Text('Standard'),
                        ),
                        ButtonSegment(
                          value: MapType.satellite,
                          icon: Icon(Icons.satellite),
                          label: Text('Satellite'),
                        ),
                        ButtonSegment(
                          value: MapType.minimal,
                          icon: Icon(Icons.layers),
                          label: Text('Minimal'),
                        ),
                      ],
                      selected: {state.mapType},
                      onSelectionChanged: (Set<MapType> newSelection) {
                        context.read<MapSettingsCubit>().setMapType(
                          newSelection.first,
                        );
                      },
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Minimal Map Theme',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto),
                          label: Text('System'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {state.themeMode},
                      onSelectionChanged: (Set<ThemeMode> newSelection) {
                        context.read<MapSettingsCubit>().setMapTheme(
                          newSelection.first,
                        );
                      },
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Show Map Controls'),
                      subtitle: const Text('Zoom buttons and center location'),
                      value: state.showControls,
                      onChanged: (bool value) {
                        // Ensure it's correctly matching state even if toggled quickly
                        if (value != state.showControls) {
                          context.read<MapSettingsCubit>().toggleControls();
                        }
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Distance Unit',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<DistanceUnit>(
                      segments: const [
                        ButtonSegment(
                          value: DistanceUnit.metric,
                          label: Text('Metric (km)'),
                        ),
                        ButtonSegment(
                          value: DistanceUnit.imperial,
                          label: Text('Imperial (mi)'),
                        ),
                      ],
                      selected: {state.distanceUnit},
                      onSelectionChanged: (Set<DistanceUnit> newSelection) {
                        context.read<MapSettingsCubit>().setDistanceUnit(
                          newSelection.first,
                        );
                      },
                      showSelectedIcon: false,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              'Location',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            BlocBuilder<LocationBloc, LocationState>(
              builder: (context, state) {
                if (state is LocationLoading) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                return OutlinedButton.icon(
                  onPressed: () {
                    context.read<LocationBloc>().add(RequestPermission());
                  },
                  icon: const Icon(Icons.my_location),
                  label: const Text('Use Current Location'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
