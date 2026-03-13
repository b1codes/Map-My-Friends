import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/person.dart';
import '../../bloc/people/people_bloc.dart';
import '../../components/map/custom_map_marker.dart';
import '../../components/shared/nearby_airports_section.dart';
import '../../components/shared/nearby_stations_section.dart';
import 'add_edit_person_screen.dart';

class PersonDetailsScreen extends StatelessWidget {
  final String personId;

  const PersonDetailsScreen({super.key, required this.personId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PeopleBloc, PeopleState>(
      builder: (context, state) {
        if (state is! PeopleLoaded) {
          // Fallback if accessed while not loaded, though rare
          return Scaffold(
            appBar: AppBar(title: const Text('Person Details')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // Find the person
        final personIndex = state.people.indexWhere((p) => p.id == personId);

        if (personIndex == -1) {
          return Scaffold(
            appBar: AppBar(title: const Text('Person Not Found')),
            body: const Center(child: Text('This person no longer exists.')),
          );
        }

        final person = state.people[personIndex];

        return Scaffold(
          appBar: AppBar(
            title: Text('${person.firstName} ${person.lastName}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddEditPersonScreen(person: person),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () {
                  context.read<PeopleBloc>().add(DeletePerson(person.id));
                  Navigator.pop(context);
                },
                color: Theme.of(context).colorScheme.error,
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 600;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isDesktop ? 600 : double.infinity,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 24.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildProfileHeader(context, person),
                        const SizedBox(height: 32),
                        _buildInfoSection(context, person),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildProfileHeader(BuildContext context, Person person) {
    String? timeString;
    if (person.timezone != null && person.timezone!.isNotEmpty) {
      try {
        final location = tz.getLocation(person.timezone!);
        final now = tz.TZDateTime.now(location);
        timeString = DateFormat.jm().format(now);
      } catch (_) {}
    }

    return Column(
      children: [
        CircleAvatar(
          radius: 64,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          backgroundImage: person.profileImageUrl != null
              ? NetworkImage(person.profileImageUrl!)
              : null,
          child: person.profileImageUrl == null
              ? Icon(
                  Icons.person,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          '${person.firstName} ${person.lastName}',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            person.relationshipTag,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (timeString != null) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.access_time,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Local Time: $timeString',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildInfoSection(BuildContext context, Person person) {
    final hasAddress =
        person.street?.isNotEmpty == true ||
        person.city.isNotEmpty ||
        person.state.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasAddress) ...[
          _buildSectionTitle(context, 'Location'),
          const SizedBox(height: 8),
          _buildInfoCard(
            context,
            icon: Icons.location_on_outlined,
            title: 'Address',
            content: [
              if (person.street?.isNotEmpty == true) person.street!,
              '${person.city}, ${person.state} ${person.country}'.trim(),
            ].join('\n'),
          ),
          const SizedBox(height: 24),
        ],

        if (person.phoneNumber?.isNotEmpty == true ||
            person.birthday != null) ...[
          _buildSectionTitle(context, 'Contact & Personal'),
          const SizedBox(height: 8),

          if (person.phoneNumber?.isNotEmpty == true) ...[
            _buildInfoCard(
              context,
              icon: Icons.phone_outlined,
              title: 'Phone Number',
              content: person.phoneNumber!,
              onTap: () {
                final uri = Uri(scheme: 'tel', path: person.phoneNumber);
                launchUrl(uri);
              },
            ),
            const SizedBox(height: 12),
          ],

          if (person.birthday != null)
            _buildInfoCard(
              context,
              icon: Icons.cake_outlined,
              title: 'Birthday',
              content: DateFormat.yMMMMd().format(person.birthday!),
            ),
        ],

        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Map Pin'),
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              CustomMapMarker(
                pinColorHex: person.pinColor,
                pinStyle: person.pinStyle,
                pinIconType: person.pinIconType,
                pinEmoji: person.pinEmoji,
                initials: _getInitials(person),
                profileImageUrl: person.profileImageUrl,
              ),
              const SizedBox(height: 8),
              Text('Preview', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (person.latitude != null && person.longitude != null) ...[
          const SizedBox(height: 24),
          NearbyAirportsSection(
            latitude: person.latitude!,
            longitude: person.longitude!,
          ),
          NearbyStationsSection(
            latitude: person.latitude!,
            longitude: person.longitude!,
          ),
        ],
      ],
    );
  }

  String _getInitials(Person person) {
    String initials = '';
    if (person.firstName.isNotEmpty) initials += person.firstName[0];
    if (person.lastName.isNotEmpty) initials += person.lastName[0];
    return initials;
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String content,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(content, style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
