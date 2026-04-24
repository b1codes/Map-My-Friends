import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/airport/airport_bloc.dart';
import '../../bloc/airport/airport_event.dart';
import '../../bloc/airport/airport_state.dart';
import '../../bloc/map/map_settings_cubit.dart';
import '../../utils/unit_converter.dart';

/// A reusable widget that shows the nearest airports to a given coordinate.
/// Used on both PersonDetailsScreen and MeScreen.
class NearbyAirportsSection extends StatefulWidget {
  final double latitude;
  final double longitude;

  const NearbyAirportsSection({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<NearbyAirportsSection> createState() => _NearbyAirportsSectionState();
}

class _NearbyAirportsSectionState extends State<NearbyAirportsSection> {
  late final AirportBloc _airportBloc;

  @override
  void initState() {
    super.initState();
    // Create a separate bloc instance for nearest airports
    _airportBloc = AirportBloc();
    _airportBloc.add(
      LoadNearestAirports(
        latitude: widget.latitude,
        longitude: widget.longitude,
      ),
    );
  }

  @override
  void dispose() {
    _airportBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distanceUnit = context.watch<MapSettingsCubit>().state.distanceUnit;

    return BlocProvider.value(
      value: _airportBloc,
      child: BlocBuilder<AirportBloc, AirportState>(
        builder: (context, state) {
          if (state is AirportLoading) {
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

          if (state is NearestAirportsLoaded && state.airports.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nearby Airports',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                ...state.airports.map(
                  (airport) => Card(
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
                              color: const Color(
                                0xFF1565C0,
                              ).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.flight,
                              color: Color(0xFF1565C0),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      airport.iataCode,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF1565C0),
                                          ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        airport.name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  airport.city.isNotEmpty
                                      ? airport.city
                                      : airport.country,
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
                          if (airport.distanceKm != null)
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
                                UnitConverter.formatDistance(
                                  airport.distanceKm,
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

          if (state is AirportError) {
            return const SizedBox.shrink();
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}
