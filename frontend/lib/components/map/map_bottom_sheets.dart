import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/airport.dart';
import '../../models/station.dart';
import '../../bloc/trip/trip_bloc.dart';
import '../../bloc/trip/trip_event.dart';
import '../shared/glass_surfaces.dart';
import '../shared/glass_inlay.dart';
import '../shared/thermal_button.dart';
import '../../utils/app_theme.dart';

class AirportBottomSheet extends StatelessWidget {
  final Airport airport;
  const AirportBottomSheet({super.key, required this.airport});
  @override
  Widget build(BuildContext context) {
    final typeLabel = airport.airportType == 'large_airport'
        ? 'International Airport'
        : 'Regional Airport';
    return BaseBottomSheet(
      icon: Icons.flight,
      color: MapPalette.airport,
      title: airport.name,
      subtitle: airport.iataCode,
      location: '${airport.city}, ${airport.country}',
      label: typeLabel,
      onAddToTrip: () {
        context.read<TripBloc>().add(AddAirportStop(airport));
        Navigator.pop(context);
        GlassToast.show(context, 'Added ${airport.name} to trip');
      },
    );
  }
}

class StationBottomSheet extends StatelessWidget {
  final Station station;
  const StationBottomSheet({super.key, required this.station});
  @override
  Widget build(BuildContext context) {
    IconData iconData = Icons.train;
    Color color = MapPalette.majorStation;
    String label = 'Station';

    switch (station.stationType) {
      case 'major_station':
        iconData = Icons.train;
        color = MapPalette.majorStation;
        label = 'Major Station';
        break;
      case 'commuter_rail_station':
        iconData = Icons.directions_railway;
        color = MapPalette.commuterRail;
        label = 'Commuter Rail';
        break;
      case 'subway_station':
        iconData = Icons.subway;
        color = MapPalette.subway;
        label = 'Subway Station';
        break;
      case 'regional_station':
        iconData = Icons.train;
        color = MapPalette.regionalStation;
        label = 'Regional Station';
        break;
      default:
        label = station.stationType ?? 'Station';
    }

    return BaseBottomSheet(
      icon: iconData,
      color: color,
      title: station.name,
      subtitle: station.uicRef != null && station.uicRef!.isNotEmpty
          ? 'Ref: ${station.uicRef}'
          : null,
      location:
          '${station.city ?? "Unknown City"}, ${station.country ?? "Unknown Country"}',
      label: label,
      onAddToTrip: () {
        context.read<TripBloc>().add(AddStationStop(station));
        Navigator.pop(context);
        GlassToast.show(context, 'Added ${station.name} to trip');
      },
    );
  }
}

class BaseBottomSheet extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String location;
  final String label;
  final VoidCallback? onAddToTrip;

  const BaseBottomSheet({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    required this.location,
    required this.label,
    this.onAddToTrip,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    // This is the cheapest refraction in the app: a live map is already behind
    // the sheet, so the material costs one backdrop sample and returns the
    // whole point of the design system. It was spending it on `cardColor`.
    return GlassSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GlassInlay(
            strong: true,
            edge: false,
            borderRadius: MapGlass.radiusPill,
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.headlineSmall?.copyWith(color: color),
            ),
          ],
          const SizedBox(height: MapSpacing.xs),
          Text(
            location,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: onSurface.withValues(alpha: 0.5),
            ),
          ),
          if (onAddToTrip != null) ...<Widget>[
            const SizedBox(height: MapSpacing.md),
            ThermalButton(
              label: 'Add to Trip',
              icon: Icons.add_location_alt_outlined,
              onPressed: onAddToTrip,
              expand: true,
            ),
          ],
        ],
      ),
    );
  }
}
