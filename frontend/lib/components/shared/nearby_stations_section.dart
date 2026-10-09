import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/station/station_bloc.dart';
import '../../bloc/station/station_event.dart';
import '../../bloc/station/station_state.dart';
import '../../bloc/map/map_settings_cubit.dart';
import '../../utils/unit_converter.dart';
import '../../utils/app_theme.dart';
import 'glass_inlay.dart';
import 'chromatic_pulse.dart';

/// A reusable widget that shows the nearest train stations to a given coordinate.
/// Used on both PersonDetailsScreen and MeScreen.
class NearbyStationsSection extends StatefulWidget {
  final double latitude;
  final double longitude;

  /// Supplies the bloc instead of creating one, so a test or the Widgetbook
  /// catalog can pin the section to a state without the network. The section
  /// neither loads nor closes a bloc it was given; the caller owns it.
  final StationBloc? bloc;

  const NearbyStationsSection({
    super.key,
    required this.latitude,
    required this.longitude,
    this.bloc,
  });

  @override
  State<NearbyStationsSection> createState() => _NearbyStationsSectionState();
}

class _NearbyStationsSectionState extends State<NearbyStationsSection> {
  late final StationBloc _stationBloc;
  late final bool _ownsBloc;

  @override
  void initState() {
    super.initState();
    final given = widget.bloc;
    _ownsBloc = given == null;
    if (given != null) {
      _stationBloc = given;
      return;
    }
    // Create a separate bloc instance for nearest stations
    _stationBloc = StationBloc();
    _stationBloc.add(
      FetchNearestStations(
        latitude: widget.latitude,
        longitude: widget.longitude,
        count: 3,
      ),
    );
  }

  @override
  void dispose() {
    if (_ownsBloc) _stationBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distanceUnit = context.watch<MapSettingsCubit>().state.distanceUnit;

    return BlocProvider.value(
      value: _stationBloc,
      child: BlocBuilder<StationBloc, StationState>(
        builder: (context, state) {
          if (state is StationLoading) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: MapSpacing.sm),
              child: PulseIndicator(size: 24),
            );
          }

          if (state is NearestStationsLoaded && state.stations.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text(
                  'Nearby Train Stations',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                ...state.stations.map(
                  (station) => Padding(
                    padding: const EdgeInsets.only(bottom: MapSpacing.xs),
                    child: GlassInlay(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFE65100,
                              ).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.train,
                              color: MapPalette.majorStation,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  station.name,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  station.city?.isNotEmpty == true
                                      ? station.city!
                                      : station.country ?? 'USA',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (station.distanceKm != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: MapGlass.inlayFillStrong(
                                  Theme.of(context).brightness,
                                ),
                                borderRadius: BorderRadius.circular(
                                  MapGlass.radiusSm,
                                ),
                              ),
                              child: Text(
                                UnitConverter.formatDistance(
                                  station.distanceKm,
                                  distanceUnit,
                                ),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}
