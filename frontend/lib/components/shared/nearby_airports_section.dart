import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/airport/airport_bloc.dart';
import '../../bloc/airport/airport_event.dart';
import '../../bloc/airport/airport_state.dart';
import '../../bloc/map/map_settings_cubit.dart';
import '../../utils/unit_converter.dart';
import '../../utils/app_theme.dart';
import 'glass_inlay.dart';
import 'nearby_blocs.dart';
import 'chromatic_pulse.dart';

/// A reusable widget that shows the nearest airports to a given coordinate.
/// Used on both PersonDetailsScreen and MeScreen.
///
/// Loads its own bloc unless a [NearbyBlocs] is provided above it.
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
  /// Created on first build, and only if no [NearbyBlocs] is provided.
  AirportBloc? _ownBloc;

  AirportBloc _createOwnBloc() {
    // A separate bloc instance from the map's, for the nearest airports
    final bloc = AirportBloc();
    _load(bloc);
    return bloc;
  }

  void _load(AirportBloc bloc) {
    bloc.add(
      LoadNearestAirports(
        latitude: widget.latitude,
        longitude: widget.longitude,
      ),
    );
  }

  @override
  void didUpdateWidget(NearbyAirportsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The person's address was edited, or the device moved.
    final own = _ownBloc;
    if (own != null &&
        (widget.latitude != oldWidget.latitude ||
            widget.longitude != oldWidget.longitude)) {
      _load(own);
    }
  }

  @override
  void dispose() {
    _ownBloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distanceUnit = context.watch<MapSettingsCubit>().state.distanceUnit;
    // Watched, so a provided bloc that changes is picked up.
    final bloc =
        context.watch<NearbyBlocs?>()?.airports ??
        (_ownBloc ??= _createOwnBloc());

    return BlocProvider.value(
      value: bloc,
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
