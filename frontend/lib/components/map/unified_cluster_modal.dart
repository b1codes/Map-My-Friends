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

import '../../components/map/map_bottom_sheets.dart';

class UnifiedClusterModal extends StatelessWidget {
  final List<dynamic> items;
  final VoidCallback? onZoom;

  const UnifiedClusterModal({super.key, required this.items, this.onZoom});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 32),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                items.length == 1
                    ? '1 Item Here'
                    : '${items.length} Items Here',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (existingStopIndex == -1)
                IconButton(
                  icon: const Icon(
                    Icons.add_location_alt_outlined,
                    color: Colors.indigo,
                  ),
                  tooltip: 'Add as New Stop',
                  onPressed: () {
                    context.read<TripBloc>().add(AddStop(p));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added ${p.firstName} as new stop'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              // Link to existing airport/station stop if one exists
              if (state.stops.any(
                (s) => s.airport != null || s.station != null,
              ))
                PopupMenuButton<int>(
                  icon: const Icon(Icons.link, color: Colors.amber),
                  tooltip: 'Link to Stop',
                  onSelected: (index) {
                    final stop = state.stops[index];
                    context.read<TripBloc>().add(LinkPersonToStop(p, index));

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Linked ${p.firstName} to stop ${String.fromCharCode(65 + index)}',
                        ),
                        duration: const Duration(seconds: 4),
                        action: SnackBarAction(
                          label: 'Set as Preferred',
                          onPressed: () {
                            final updatedPerson = p.copyWith(
                              preferredAirportId: stop.airport?.id?.toString(),
                              preferredStationId: stop.station?.id?.toString(),
                              preferredAirport: stop.airport,
                              preferredStation: stop.station,
                            );
                            context.read<PeopleBloc>().add(
                              UpdatePerson(updatedPerson),
                            );
                          },
                        ),
                      ),
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
          color: const Color(0xFF1565C0).withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.flight, color: Color(0xFF1565C0), size: 24),
      ),
      title: Text(a.name),
      subtitle: Text(
        '${a.iataCode} • ${a.city}, ${a.country}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(
              Icons.add_location_alt_outlined,
              color: Colors.indigo,
            ),
            tooltip: 'Add to Trip',
            onPressed: () {
              context.read<TripBloc>().add(AddAirportStop(a));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added ${a.name} to trip'),
                  duration: const Duration(seconds: 2),
                ),
              );
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
    Color color = const Color(0xFFE65100);
    String label = 'Station';

    switch (s.stationType) {
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
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(
              Icons.add_location_alt_outlined,
              color: Colors.indigo,
            ),
            tooltip: 'Add to Trip',
            onPressed: () {
              context.read<TripBloc>().add(AddStationStop(s));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added ${s.name} to trip'),
                  duration: const Duration(seconds: 2),
                ),
              );
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
