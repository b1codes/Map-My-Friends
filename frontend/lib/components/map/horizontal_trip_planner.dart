import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../bloc/trip/trip_bloc.dart';
import '../../bloc/trip/trip_event.dart';
import '../../bloc/trip/trip_state.dart';
import '../../models/trip.dart';
import '../shared/glass_container.dart';

class HorizontalTripPlanner extends StatelessWidget {
  const HorizontalTripPlanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TripBloc, TripState>(
      builder: (context, state) {
        if (state.stops.isEmpty) {
          return const SizedBox.shrink();
        }

        return Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: GlassContainer(
            height: 140,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: state.stops.length,
                    itemBuilder: (context, index) {
                      final stop = state.stops[index];
                      final isPerson = stop.person != null;
                      final letter = String.fromCharCode(65 + index);

                      return Container(
                        width: 80,
                        margin: const EdgeInsets.only(right: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              backgroundColor: isPerson
                                  ? Colors.amber
                                  : Colors.indigo,
                              child: Text(
                                letter,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              stop.person?.firstName ?? "Stop",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const VerticalDivider(
                  width: 24,
                  thickness: 1,
                  color: Colors.white24,
                ),
                _ActionGroup(
                  onSave: () {
                    final now = DateTime.now();
                    final dateStr = DateFormat('yyyy-MM-dd').format(now);
                    context.read<TripBloc>().add(
                      SaveTrip(
                        name: "Draft Trip $dateStr",
                        date: now,
                        status: TripStatus.draft,
                      ),
                    );
                  },
                  onClear: () {
                    context.read<TripBloc>().add(const ClearTrip());
                  },
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
          onPressed: onSave,
          tooltip: 'Save Trip',
        ),
        IconButton(
          icon: const Icon(Icons.layers_clear, color: Colors.redAccent),
          onPressed: onClear,
          tooltip: 'Clear Trip',
        ),
      ],
    );
  }
}
