import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/trip/trip_bloc.dart';
import '../../bloc/trip/trip_event.dart';
import '../../bloc/trip/trip_state.dart';
import '../../components/shared/glass_container.dart';

class TripPlannerSheet extends StatelessWidget {
  const TripPlannerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.1,
      minChildSize: 0.1,
      maxChildSize: 0.8,
      builder: (context, scrollController) {
        return BlocBuilder<TripBloc, TripState>(
          builder: (context, state) {
            return GlassContainer(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Trip Planner',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${state.stops.length} stops',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (state.stops.isNotEmpty)
                          IconButton(
                            onPressed: () => _showClearConfirmation(context),
                            icon: const Icon(Icons.delete_sweep_outlined),
                            tooltip: 'Clear Trip',
                          ),
                        if (state.stops.length > 2 || state.isOptimizing)
                          state.isOptimizing
                              ? const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : TextButton.icon(
                                  onPressed: () => context.read<TripBloc>().add(
                                    OptimizeTrip(),
                                  ),
                                  icon: const Icon(Icons.auto_fix_high),
                                  label: const Text('Optimize'),
                                ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: state.stops.isEmpty
                        ? ListView(
                            controller: scrollController,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(64.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.map_outlined,
                                      size: 48,
                                      color: Colors.white24,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Add friends from the map to start planning your trip!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ReorderableListView.builder(
                            scrollController: scrollController,
                            itemCount: state.stops.length,
                            itemBuilder: (context, index) {
                              final stop = state.stops[index];
                              final String title = stop.person != null
                                  ? '${stop.person!.firstName} ${stop.person!.lastName}'
                                  : 'Generic Stop ${index + 1}';

                              return ListTile(
                                key: ValueKey(stop.id),
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  child: Text(
                                    String.fromCharCode(65 + index),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  '${stop.location.latitude.toStringAsFixed(4)}, ${stop.location.longitude.toStringAsFixed(4)}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 20),
                                      onPressed: () => context
                                          .read<TripBloc>()
                                          .add(RemoveStop(index)),
                                    ),
                                    const Icon(Icons.drag_handle),
                                  ],
                                ),
                              );
                            },
                            onReorder: (oldIdx, newIdx) => context
                                .read<TripBloc>()
                                .add(ReorderStops(oldIdx, newIdx)),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showClearConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Trip'),
        content: const Text(
          'Are you sure you want to clear all stops from your trip?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<TripBloc>().add(ClearTrip());
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
