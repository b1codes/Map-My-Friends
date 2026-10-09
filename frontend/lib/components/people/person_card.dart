import 'package:flutter/material.dart';
import '../../models/person.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import '../shared/glass_inlay.dart';
import '../shared/thermal_response.dart';
import '../../utils/app_theme.dart';

class PersonCard extends StatelessWidget {
  final Person person;
  final VoidCallback onTap;

  const PersonCard({super.key, required this.person, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String? timeString;
    if (person.timezone != null && person.timezone!.isNotEmpty) {
      try {
        final location = tz.getLocation(person.timezone!);
        final now = tz.TZDateTime.now(location);
        timeString = DateFormat.jm().format(now);
      } catch (_) {
        // Ignore invalid timezones
      }
    }

    return ThermalResponse(
      onTap: onTap,
      borderRadius: MapGlass.radiusMd,
      child: GlassInlay(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${person.firstName} ${person.lastName}',
              // titleMedium, not a hand-set 16/bold: this line silently lost
              // Montserrat the moment it stopped reading from the scale.
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${person.city}, ${person.state}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: MapSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  person.relationshipTag,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (timeString != null)
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeString,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
