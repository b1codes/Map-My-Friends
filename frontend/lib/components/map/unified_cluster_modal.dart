import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/person.dart';
import '../../models/airport.dart';
import '../../models/station.dart';
import '../../screens/people/person_details_screen.dart';
import '../../bloc/trip/trip_bloc.dart';
import '../../bloc/trip/trip_event.dart';
import '../../bloc/trip/trip_state.dart';
import '../../bloc/people/people_bloc.dart';
import '../../utils/app_theme.dart';

import '../../components/map/map_bottom_sheets.dart';
import '../shared/glass_surfaces.dart';

class UnifiedClusterModal extends StatelessWidget {
  final List<dynamic> items;
  final VoidCallback? onZoom;

  const UnifiedClusterModal({super.key, required this.items, this.onZoom});

  @override
  Widget build(BuildContext context) {
    // Over a live map: the one place refraction costs nothing extra, because
    // the scene behind the sheet is already being drawn.
    return GlassSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                items.length == 1
                    ? '1 Item Here'
                    : '${items.length} Items Here',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (onZoom != null && items.length > 1)
                TextButton.icon(
                  onPressed: onZoom,
                  icon: const Icon(Icons.zoom_in),
                  label: const Text('Zoom to Area'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final item = items[index];
                if (item is Person) {
                  return _buildPersonTile(context, item);
                } else if (item is Airport) {
                  return _buildAirportTile(context, item);
                } else if (item is Station) {
                  return _buildStationTile(context, item);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonTile(BuildContext context, Person p) {
    return BlocBuilder<TripBloc, TripState>(
      builder: (context, state) {
        final existingStopIndex = state.stops.indexWhere(
          (s) => s.people.any((person) => person.id == p.id),
        );

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            backgroundImage: p.profileImageUrl != null
                ? NetworkImage(p.profileImageUrl!)
                : null,
            child: p.profileImageUrl == null
                ? Text(
                    (p.firstName.isNotEmpty ? p.firstName[0] : '') +
                        (p.lastName.isNotEmpty ? p.lastName[0] : ''),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          title: Text('${p.firstName} ${p.lastName}'),
          subtitle: Text(
            p.relationshipTag,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (existingStopIndex == -1)
                IconButton(
                  icon: Icon(
                    Icons.add_location_alt_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  tooltip: 'Add as New Stop',
                  onPressed: () {
                    context.read<TripBloc>().add(AddStop(p));
                    GlassToast.show(
                      context,
                      'Added ${p.firstName} as new stop',
                    );
                  },
                ),
              // Link to existing airport/station stop if one exists
              if (state.stops.any(
                (s) => s.airport != null || s.station != null,
              ))
                PopupMenuButton<int>(
                  icon: Icon(
                    Icons.link,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  tooltip: 'Link to Stop',
                  onSelected: (index) {
                    final stop = state.stops[index];
                    final tripBloc = context.read<TripBloc>();
                    final peopleBloc = context.read<PeopleBloc>();

                    tripBloc.add(LinkPersonToStop(p, index));

                    GlassToast.show(
                      context,
                      'Linked ${p.firstName} to stop ${String.fromCharCode(65 + index)}',
                      actionLabel: 'Set as Preferred',
                      onAction: () {
                        final updatedPerson = p.copyWith(
                          preferredAirportId: stop.airport?.id?.toString(),
                          preferredStationId: stop.station?.id?.toString(),
                          preferredAirport: stop.airport,
                          preferredStation: stop.station,
                        );
                        peopleBloc.add(UpdatePerson(updatedPerson));
                      },
                    );
                  },
                  itemBuilder: (context) {
                    return state.stops
                        .asMap()
                        .entries
                        .where(
                          (e) =>
                              e.value.airport != null ||
                              e.value.station != null,
                        )
                        .map((e) {
                          final stop = e.value;
                          final label = stop.airport != null
                              ? 'Airport ${stop.airport!.iataCode}'
                              : 'Station ${stop.station!.name}';
                          return PopupMenuItem<int>(
                            value: e.key,
                            child: Text(
                              '${String.fromCharCode(65 + e.key)}: $label',
                            ),
                          );
                        })
                        .toList();
                  },
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () {
            Navigator.pop(context); // close modal
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PersonDetailsScreen(personId: p.id),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAirportTile(BuildContext context, Airport a) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: MapPalette.airport.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.flight, color: MapPalette.airport, size: 24),
      ),
      title: Text(a.name),
      subtitle: Text(
        '${a.iataCode} • ${a.city}, ${a.country}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              Icons.add_location_alt_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            tooltip: 'Add to Trip',
            onPressed: () {
              context.read<TripBloc>().add(AddAirportStop(a));
              GlassToast.show(context, 'Added ${a.name} to trip');
            },
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () {
        Navigator.pop(context); // close modal
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => AirportBottomSheet(airport: a),
        );
      },
    );
  }

  Widget _buildStationTile(BuildContext context, Station s) {
    IconData iconData = Icons.train;
    Color color = MapPalette.majorStation;
    String label = 'Station';

    switch (s.stationType) {
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
        label = s.stationType ?? 'Station';
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(iconData, color: color, size: 24),
      ),
      title: Text(s.name),
      subtitle: Text(
        '$label • ${s.city ?? "Unknown City"}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              Icons.add_location_alt_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            tooltip: 'Add to Trip',
            onPressed: () {
              context.read<TripBloc>().add(AddStationStop(s));
              GlassToast.show(context, 'Added ${s.name} to trip');
            },
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () {
        Navigator.pop(context); // close modal
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => StationBottomSheet(station: s),
        );
      },
    );
  }
}
