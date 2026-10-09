import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../bloc/trip/trip_bloc.dart';
import '../../bloc/trip/trip_event.dart';
import '../../bloc/trip/trip_state.dart';
import '../../models/trip.dart';
import '../../components/shared/glass_container.dart';
import '../../components/shared/glass_empty_state.dart';
import 'trip_details_screen.dart';
import '../../utils/app_theme.dart';
import '../../components/shared/chromatic_pulse.dart';
import '../../components/shared/glass_surfaces.dart';
import '../../components/shared/glass_inlay.dart';
import '../../components/shared/thermal_response.dart';
import '../../components/shared/thermal_button.dart';

class TripsScreen extends StatelessWidget {
  final VoidCallback onNavigateToMap;
  const TripsScreen({super.key, required this.onNavigateToMap});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              Expanded(child: _buildTripsList(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Trips',
          style: theme.textTheme.headlineLarge?.copyWith(color: onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage your planned and booked adventures',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildTripsList(BuildContext context) {
    return BlocBuilder<TripBloc, TripState>(
      builder: (context, state) {
        if (state.isLoading && state.userTrips.isEmpty) {
          return const PulseIndicator();
        }

        if (state.userTrips.isEmpty) {
          return _buildEmptyState(context);
        }

        // Group trips by status
        final booked = state.userTrips
            .where((t) => t.status == TripStatus.booked)
            .toList();
        final drafts = state.userTrips
            .where((t) => t.status == TripStatus.draft)
            .toList();
        final cancelled = state.userTrips
            .where((t) => t.status == TripStatus.cancelled)
            .toList();

        // Flatten to section headers + cards so the list can virtualise.
        // A plain ListView built every card eagerly, which meant one live
        // glass surface per trip in the user's whole history — off-screen
        // ones included. ListView.builder holds that to the visible window.
        final rows = <_TripRow>[
          if (booked.isNotEmpty) ..._sectionRows('Booked', booked),
          if (drafts.isNotEmpty) ..._sectionRows('Drafts', drafts),
          if (cancelled.isNotEmpty) ..._sectionRows('Cancelled', cancelled),
        ];

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return row.trip == null
                ? _buildSectionHeader(context, row.title!)
                : _buildTripCard(context, row.trip!);
          },
        );
      },
    );
  }

  List<_TripRow> _sectionRows(String title, List<Trip> trips) {
    return [_TripRow.header(title), ...trips.map(_TripRow.card)];
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildTripCard(BuildContext context, Trip trip) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final bool isCurrent =
        context.watch<TripBloc>().state.currentTripId == trip.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GlassContainer(
        padding: EdgeInsets.zero,
        borderRadius: MapGlass.radiusMd,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getStatusColor(
                context,
                trip.status,
              ).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getStatusIcon(trip.status),
              color: _getStatusColor(context, trip.status),
            ),
          ),
          title: Text(
            trip.name,
            style: theme.textTheme.titleLarge?.copyWith(
              color: onSurface,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            '${DateFormat('MMM d').format(trip.startDate ?? trip.date)}${trip.endDate != null && trip.endDate != trip.startDate ? ' - ${DateFormat('MMM d').format(trip.endDate!)}' : ''} • ${trip.stops.length} stops',
            style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
          ),
          trailing: PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: onSurface.withValues(alpha: 0.7),
            ),
            onSelected: (value) => _handleMenuAction(context, value, trip),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'load', child: Text('View on Map')),
              const PopupMenuItem(
                value: 'status',
                child: Text('Update Status'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
          onTap: () {
            if (trip.status == TripStatus.booked) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TripDetailsScreen(trip: trip),
                ),
              );
            } else {
              context.read<TripBloc>().add(LoadTrip(trip));
              onNavigateToMap();
            }
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return GlassEmptyState(
      icon: Icons.route_outlined,
      title: 'No Trips Yet',
      message: 'Plan your first route on the map!',
      actionLabel: 'Start Planning',
      onAction: onNavigateToMap,
    );
  }

  void _handleMenuAction(BuildContext context, String action, Trip trip) {
    switch (action) {
      case 'load':
        context.read<TripBloc>().add(LoadTrip(trip));
        onNavigateToMap();
        break;
      case 'status':
        _showStatusUpdateDialog(context, trip);
        break;
      case 'delete':
        _showDeleteConfirmation(context, trip);
        break;
    }
  }

  void _showStatusUpdateDialog(BuildContext context, Trip trip) {
    // Choosing a status *is* the dialog, so each option is a thermal row that
    // commits on tap. A radio plus a confirm button would be two steps for a
    // decision the user already made when they touched the row.
    GlassDialog.panel(
      context,
      title: 'Update Trip Status',
      dismissLabel: 'Close',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: TripStatus.values.map((status) {
          final bool selected = status == trip.status;
          return Padding(
            padding: const EdgeInsets.only(bottom: MapSpacing.xs),
            child: ThermalResponse(
              borderRadius: MapGlass.radiusSm,
              onTap: () {
                context.read<TripBloc>().add(
                  SaveTrip(
                    name: trip.name,
                    startDate: trip.startDate,
                    endDate: trip.endDate,
                    status: status,
                  ),
                );
                Navigator.pop(context);
              },
              child: GlassInlay(
                strong: selected,
                borderRadius: MapGlass.radiusSm,
                padding: const EdgeInsets.symmetric(
                  horizontal: MapSpacing.sm,
                  vertical: 14,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _getStatusIcon(status),
                      size: 18,
                      color: _getStatusColor(context, status),
                    ),
                    const SizedBox(width: MapSpacing.sm),
                    Expanded(
                      child: Text(
                        status.name.toUpperCase(),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Trip trip) {
    // The destructive answer carries the thermal core and the cancel does not,
    // so the dangerous option is the one that looks dangerous — Material gave
    // both the same text-button weight.
    GlassDialog.confirm(
      context,
      title: 'Delete Trip',
      message:
          'This removes "${trip.name}" and its itinerary. It cannot be '
          'undone.',
      confirmLabel: 'Delete',
      tone: ThermalButtonTone.danger,
    ).then((confirmed) {
      if (!confirmed || !context.mounted) return;
      context.read<TripBloc>().add(DeleteTrip(trip.id!));
    });
  }

  IconData _getStatusIcon(TripStatus status) {
    switch (status) {
      case TripStatus.booked:
        return Icons.check_circle_outline;
      case TripStatus.cancelled:
        return Icons.cancel_outlined;
      default:
        return Icons.edit_note;
    }
  }

  Color _getStatusColor(BuildContext context, TripStatus status) {
    final brightness = Theme.of(context).brightness;
    switch (status) {
      case TripStatus.booked:
        return MapPalette.journeyConfirmed.ink(brightness);
      case TripStatus.cancelled:
        return MapPalette.journeyCancelled.ink(brightness);
      default:
        return MapPalette.journeyPlanned.ink(brightness);
    }
  }
}

/// One row in the flattened trips list: either a section header or a trip card.
class _TripRow {
  final String? title;
  final Trip? trip;

  const _TripRow.header(this.title) : trip = null;
  const _TripRow.card(this.trip) : title = null;
}
