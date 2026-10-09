import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/people/people_bloc.dart';
import 'add_edit_person_screen.dart';
import 'person_details_screen.dart';
import '../../components/people/person_card.dart';
import '../../components/shared/chromatic_pulse.dart';
import '../../components/shared/glass_empty_state.dart';
import '../../components/shared/glass_header.dart';
import '../../utils/app_theme.dart';
import '../../utils/window_size.dart';

/// The people the user keeps track of.
///
/// One row for every width. This screen used to render a `PersonCard` grid on
/// desktop and a bare Material `ListTile` list on phones — two different
/// products for one entity, with the phone getting the un-designed one. The
/// layout changes with the width; what a person *is* does not.
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  void _addPerson(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddEditPersonScreen()),
    );
  }

  void _openPerson(BuildContext context, String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PersonDetailsScreen(personId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BlocBuilder<PeopleBloc, PeopleState>(
        builder: (context, state) {
          final int count = state is PeopleLoaded ? state.people.length : 0;

          return Column(
            children: <Widget>[
              GlassHeader(
                title: 'People',
                subtitle: switch (count) {
                  0 => null,
                  1 => '1 person',
                  _ => '$count people',
                },
                showBack: false,
                actions: <HeaderAction>[
                  // The add action lives in the surface's own chrome. A
                  // floating action button is Material's most recognisable
                  // single element, and it was hovering over the glass nav bar
                  // with a hand-tuned 90px offset to avoid colliding with it.
                  HeaderAction(
                    icon: Icons.person_add_alt_1,
                    label: 'Add person',
                    onPressed: () => _addPerson(context),
                  ),
                ],
              ),
              Expanded(child: _buildBody(context, state)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, PeopleState state) {
    if (state is PeopleLoading) {
      return const PulseIndicator(label: 'Loading your people');
    }

    if (state is PeopleError) {
      return GlassEmptyState(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load your people",
        message: state.message,
      );
    }

    if (state is! PeopleLoaded) {
      return const GlassEmptyState(
        icon: Icons.people_outline,
        title: 'No Friends Added Yet',
        message:
            'Add friends and family to see their locations on the map and '
            'plan shared routes.',
      );
    }

    if (state.people.isEmpty) {
      return GlassEmptyState(
        icon: Icons.people_outline,
        title: 'No Friends Added Yet',
        message:
            'Add friends and family to see their locations on the map and '
            'plan shared routes.',
        actionLabel: 'Add Your First Friend',
        actionIcon: Icons.person_add_alt_1,
        onAction: () => _addPerson(context),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final window = MapWindow(
          Size(constraints.maxWidth, constraints.maxHeight),
        );

        // Clears the floating nav bar at the bottom on phones, and the rail's
        // gutter on wide windows.
        final padding = EdgeInsets.fromLTRB(
          window.usesRail ? 96 : MapSpacing.sm,
          MapSpacing.xs,
          MapSpacing.sm,
          120,
        );

        if (!window.isWide) {
          return ListView.separated(
            padding: padding,
            itemCount: state.people.length,
            separatorBuilder: (_, _) => const SizedBox(height: MapSpacing.xs),
            itemBuilder: (context, index) {
              final person = state.people[index];
              return PersonCard(
                person: person,
                onTap: () => _openPerson(context, person.id),
              );
            },
          );
        }

        return GridView.builder(
          padding: padding,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            // Extent rather than a column count: the row has one legible
            // width, and the window decides how many of them fit.
            maxCrossAxisExtent: 420,
            mainAxisSpacing: MapSpacing.xs,
            crossAxisSpacing: MapSpacing.xs,
            mainAxisExtent: 116,
          ),
          itemCount: state.people.length,
          itemBuilder: (context, index) {
            final person = state.people[index];
            return PersonCard(
              person: person,
              onTap: () => _openPerson(context, person.id),
            );
          },
        );
      },
    );
  }
}
