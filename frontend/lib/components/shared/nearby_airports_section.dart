import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/airport/airport_bloc.dart';
import '../../bloc/airport/airport_event.dart';
import '../../bloc/airport/airport_state.dart';
import '../../bloc/map/map_settings_cubit.dart';
import '../../utils/unit_converter.dart';
import '../../utils/app_theme.dart';
import 'glass_inlay.dart';
import 'chromatic_pulse.dart';

/// A reusable widget that shows the nearest airports to a given coordinate.
/// Used on both PersonDetailsScreen and MeScreen.
class NearbyAirportsSection extends StatefulWidget {
  final double latitude;
  final double longitude;

  /// Supplies the bloc instead of creating one, so a test or the Widgetbook
  /// catalog can pin the section to a state without the network. The section
  /// neither loads nor closes a bloc it was given; the caller owns it.
  final AirportBloc? bloc;

  const NearbyAirportsSection({
    super.key,
    required this.latitude,
    required this.longitude,
    this.bloc,
  });

  @override
  State<NearbyAirportsSection> createState() => _NearbyAirportsSectionState();
}

class _NearbyAirportsSectionState extends State<NearbyAirportsSection> {
  late final AirportBloc _airportBloc;
  late final bool _ownsBloc;

  @override
  void initState() {
    super.initState();
    final given = widget.bloc;
    _ownsBloc = given == null;
    if (given != null) {
      _airportBloc = given;
      return;
    }
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
    if (_ownsBloc) _airportBloc.close();
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
              padding: EdgeInsets.symmetric(vertical: MapSpacing.sm),
              child: PulseIndicator(size: 24),
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
                  (airport) => Padding(
                    padding: const EdgeInsets.only(bottom: MapSpacing.xs),
                    child: GlassInlay(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: MapPalette.airport.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.flight,
                              color: MapPalette.airport,
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
                                            color: MapPalette.airport,
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
                                color: MapGlass.inlayFillStrong(
                                  Theme.of(context).brightness,
                                ),
                                borderRadius: BorderRadius.circular(
                                  MapGlass.radiusSm,
                                ),
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
