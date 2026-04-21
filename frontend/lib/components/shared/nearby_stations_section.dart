import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/station/station_bloc.dart';
import '../../bloc/station/station_event.dart';
import '../../bloc/station/station_state.dart';

/// A reusable widget that shows the nearest train stations to a given coordinate.
/// Used on both PersonDetailsScreen and MeScreen.
class NearbyStationsSection extends StatefulWidget {
  final double latitude;
  final double longitude;

  const NearbyStationsSection({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<NearbyStationsSection> createState() => _NearbyStationsSectionState();
}

class _NearbyStationsSectionState extends State<NearbyStationsSection> {
  late final StationBloc _stationBloc;

  @override
  void initState() {
    super.initState();
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
    _stationBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _stationBloc,
      child: BlocBuilder<StationBloc, StationState>(
        builder: (context, state) {
          if (state is StationLoading) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
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
                  (station) => Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE65100).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.train,
                              color: Color(0xFFE65100),
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${station.distanceKm!.round()} km',
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
