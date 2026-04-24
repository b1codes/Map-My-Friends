import 'package:flutter/material.dart';
import '../../models/airport.dart';
import '../../models/station.dart';

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
      color: const Color(0xFF1565C0),
      title: airport.name,
      subtitle: airport.iataCode,
      location: '${airport.city}, ${airport.country}',
      label: typeLabel,
    );
  }
}

class StationBottomSheet extends StatelessWidget {
  final Station station;
  const StationBottomSheet({super.key, required this.station});
  @override
  Widget build(BuildContext context) {
    IconData iconData = Icons.train;
    Color color = const Color(0xFFE65100);
    String label = 'Station';

    switch (station.stationType) {
      case 'major_station':
        iconData = Icons.train;
        color = const Color(0xFFE65100);
        label = 'Major Station';
        break;
      case 'commuter_rail_station':
        iconData = Icons.directions_railway;
        color = const Color(0xFF00695C);
        label = 'Commuter Rail';
        break;
      case 'subway_station':
        iconData = Icons.subway;
        color = const Color(0xFF2E7D32);
        label = 'Subway Station';
        break;
      case 'regional_station':
        iconData = Icons.train;
        color = const Color(0xFF607D8B);
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
  const BaseBottomSheet({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    required this.location,
    required this.label,
  });
  @override
  Widget build(BuildContext context) {
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
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              location,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
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
