import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../bloc/trip/trip_bloc.dart';
import '../../bloc/trip/trip_event.dart';
import '../../bloc/trip/trip_state.dart';
import '../../models/person.dart';
import '../../models/trip.dart';
import '../../utils/app_theme.dart';
import '../shared/glass_container.dart';
import '../shared/thermal_response.dart';
import '../../utils/window_size.dart';

class HorizontalTripPlanner extends StatelessWidget {
  const HorizontalTripPlanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TripBloc, TripState>(
      builder: (context, state) {
        if (state.stops.isEmpty) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final window = MapWindow.of(context);
        final bottomInset = window.usesBar
            ? MediaQuery.of(context).padding.bottom
            : 0.0;

        return Positioned(
          bottom: 24 + window.navBarInset + bottomInset,
          left: window.edgeInset,
          right: window.edgeInset,
          child: GlassContainer(
            height: 140,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: state.stops.length,
                    itemBuilder: (context, index) {
                      final stop = state.stops[index];
                      String name = 'Stop';
                      IconData? icon;
                      // Default is "person-only" — the rare Aurora Pink slot,
                      // reserved by DESIGN.md for trip-this-week markers.
                      Color color = scheme.secondary;
                      Color onColor = scheme.onSecondary;

                      if (stop.airport != null) {
                        name = stop.airport!.iataCode;
                        icon = Icons.flight;
                        color = MapPalette.airport;
                        onColor = Colors.white;
                      } else if (stop.station != null) {
                        name = stop.station!.name;
                        icon = Icons.train;
                        color = MapPalette.majorStation;
                        onColor = Colors.white;
                      } else if (stop.people.isNotEmpty) {
                        name = stop.people.first.firstName;
                        if (stop.people.length > 1) {
                          name += ' +${stop.people.length - 1}';
                        }
                      }

                      final letter = String.fromCharCode(65 + index);

                      return Container(
                        width: 120,
                        margin: const EdgeInsets.only(right: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: icon != null
                                      ? Icon(icon, size: 20, color: onColor)
                                      : Text(
                                          letter,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: onColor,
                                          ),
                                        ),
                                ),
                                if (stop.people.isNotEmpty &&
                                    (stop.airport != null ||
                                        stop.station != null))
                                  Positioned(
                                    right: -4,
                                    top: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: scheme.secondary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        stop.people.length.toString(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: scheme.onSecondary,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (stop.people.isNotEmpty &&
                                (stop.airport != null || stop.station != null))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: -8,
                                  children: stop.people.take(3).map((p) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
                                          width: 0.5,
                                        ),
                                      ),
                                      child: CircleAvatar(
                                        radius: 10,
                                        backgroundImage:
                                            p.profileImageUrl != null
                                            ? NetworkImage(p.profileImageUrl!)
                                            : null,
                                        child: p.profileImageUrl == null
                                            ? Text(
                                                _initialOf(p),
                                                style: const TextStyle(
                                                  fontSize: 8,
                                                ),
                                              )
                                            : null,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                VerticalDivider(
                  width: 24,
                  thickness: 1,
                  color: theme.dividerColor,
                ),
                SizedBox(
                  height: 140,
                  child: _ActionGroup(
                    onSave: () {
                      final now = DateTime.now();
                      final dateStr = DateFormat('yyyy-MM-dd').format(now);
                      context.read<TripBloc>().add(
                        SaveTrip(
                          name: "Draft Trip $dateStr",
                          startDate: now,
                          endDate: now,
                          status: TripStatus.draft,
                        ),
                      );
                    },
                    onClear: () {
                      context.read<TripBloc>().add(const ClearTrip());
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionGroup extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onClear;

  const _ActionGroup({required this.onSave, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ThermalResponse(
          onTap: onSave,
          borderRadius: 24,
          child: Semantics(
            label: 'Save Trip',
            button: true,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Icon(Icons.check_circle, color: scheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ThermalResponse(
          onTap: onClear,
          borderRadius: 24,
          child: Semantics(
            label: 'Clear Trip',
            button: true,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Icon(Icons.layers_clear, color: scheme.error),
            ),
          ),
        ),
      ],
    );
  }
}

/// The avatar letter for [p]: their first initial, else their last, else
/// nothing. Names come from the server, so either may be empty.
String _initialOf(Person p) {
  if (p.firstName.isNotEmpty) return p.firstName[0];
  if (p.lastName.isNotEmpty) return p.lastName[0];
  return '';
}
