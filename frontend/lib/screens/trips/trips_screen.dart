import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../bloc/trip/trip_bloc.dart';
import '../../bloc/trip/trip_event.dart';
import '../../bloc/trip/trip_state.dart';
import '../../models/trip.dart';
import '../../components/shared/glass_container.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Trips',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage your planned and booked adventures',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
        ),
      ],
    );
  }

  Widget _buildTripsList(BuildContext context) {
    return BlocBuilder<TripBloc, TripState>(
      builder: (context, state) {
        if (state.isLoading && state.userTrips.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.userTrips.isEmpty) {
          return _buildEmptyState(context);
        }

        // Group trips by status
        final booked = state.userTrips.where((t) => t.status == TripStatus.booked).toList();
        final drafts = state.userTrips.where((t) => t.status == TripStatus.draft).toList();
        final cancelled = state.userTrips.where((t) => t.status == TripStatus.cancelled).toList();

        return ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            if (booked.isNotEmpty) _buildSection(context, 'Booked', booked),
            if (drafts.isNotEmpty) _buildSection(context, 'Drafts', drafts),
            if (cancelled.isNotEmpty) _buildSection(context, 'Cancelled', cancelled),
          ],
        );
      },
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Trip> trips) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
          ),
        ),
        ...trips.map((trip) => _buildTripCard(context, trip)),
      ],
    );
  }

  Widget _buildTripCard(BuildContext context, Trip trip) {
    final bool isCurrent = context.watch<TripBloc>().state.currentTripId == trip.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GlassContainer(
        padding: EdgeInsets.zero,
        borderRadius: 16,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getStatusColor(trip.status).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getStatusIcon(trip.status),
              color: _getStatusColor(trip.status),
            ),
          ),
          title: Text(
            trip.name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
          ),
          subtitle: Text(
            '${DateFormat('MMM d, yyyy').format(trip.date)} • ${trip.stops.length} stops',
            style: const TextStyle(color: Colors.white70),
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onSelected: (value) => _handleMenuAction(context, value, trip),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'load', child: Text('View on Map')),
              const PopupMenuItem(value: 'status', child: Text('Update Status')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
          onTap: () {
            context.read<TripBloc>().add(LoadTrip(trip));
            onNavigateToMap();
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: GlassContainer(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route_outlined, size: 64, color: Colors.white24),
            const SizedBox(height: 24),
            const Text(
              'No Trips Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Plan your first route on the map!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: onNavigateToMap,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Start Planning'),
            ),
          ],
        ),
      ),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Trip Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: TripStatus.values.map((status) => ListTile(
            title: Text(status.name.toUpperCase()),
            leading: Radio<TripStatus>(
              value: status,
              groupValue: trip.status,
              onChanged: (v) {
                context.read<TripBloc>().add(SaveTrip(
                  name: trip.name,
                  date: trip.date,
                  status: v!,
                ));
                Navigator.pop(context);
              },
            ),
            onTap: () {
              context.read<TripBloc>().add(SaveTrip(
                name: trip.name,
                date: trip.date,
                status: status,
              ));
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Trip trip) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip'),
        content: Text('Are you sure you want to delete "${trip.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<TripBloc>().add(DeleteTrip(trip.id!));
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(TripStatus status) {
    switch (status) {
      case TripStatus.booked: return Icons.check_circle_outline;
      case TripStatus.cancelled: return Icons.cancel_outlined;
      default: return Icons.edit_note;
    }
  }

  Color _getStatusColor(TripStatus status) {
    switch (status) {
      case TripStatus.booked: return Colors.greenAccent;
      case TripStatus.cancelled: return Colors.redAccent;
      default: return Colors.orangeAccent;
    }
  }
}
