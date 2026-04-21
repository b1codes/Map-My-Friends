# Frontend Trips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the interactive Trip Builder and Route Visualization feature in the Flutter frontend, enabling multi-stop state management, drag-and-drop reordering, TSP optimization, and road-aware routing.

**Architecture:** A new `TripBloc` will manage the active trip state. A `RoutingService` will handle hybrid OSRM/Straight-line path calculation. The UI will feature a `DraggableScrollableSheet` with `ReorderableListView` and a `PolylineLayer` on the map.

**Tech Stack:** Flutter, BLoC, OSRM API, `flutter_map`, `latlong2`.

---

## File Map

**Create:**
- `frontend/lib/models/trip.dart`
- `frontend/lib/services/routing_service.dart`
- `frontend/lib/bloc/trip/trip_bloc.dart`
- `frontend/lib/bloc/trip/trip_event.dart`
- `frontend/lib/bloc/trip/trip_state.dart`
- `frontend/lib/screens/map/trip_planner_sheet.dart`

**Modify:**
- `frontend/lib/screens/map/map_screen.dart`
- `frontend/lib/components/map/map_controls.dart`
- `frontend/lib/main.dart` (Register the new Bloc)

---

## Task 1: Trip Data Models

- [ ] **Step 1: Create `frontend/lib/models/trip.dart`**

```dart
import 'package:latlong2/latlong.dart';
import 'person.dart';

class TripStop {
  final String id;
  final Person? person;
  final LatLng location;
  final int sequenceOrder;

  TripStop({
    required this.id,
    this.person,
    required this.location,
    required this.sequenceOrder,
  });

  TripStop copyWith({int? sequenceOrder}) {
    return TripStop(
      id: id,
      person: person,
      location: location,
      sequenceOrder: sequenceOrder ?? this.sequenceOrder,
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/models/trip.dart
git commit -m "feat: add TripStop data model"
```

---

## Task 2: Routing Service

- [ ] **Step 1: Create `frontend/lib/services/routing_service.dart`**

```dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class RoutingService {
  final Dio _dio = Dio();

  Future<List<LatLng>> getRoute(List<LatLng> points) async {
    if (points.length < 2) return [];

    try {
      final coordinates = points
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');
      
      final url = 'https://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=geojson';
      
      final response = await _dio.get(url);
      
      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> coords = data['routes'][0]['geometry']['coordinates'];
        return coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
      }
    } catch (e) {
      print('Routing error: $e');
    }
    
    // Fallback to straight lines
    return points;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/services/routing_service.dart
git commit -m "feat: add RoutingService for OSRM path calculation"
```

---

## Task 3: Trip BLoC (State, Events, Logic)

- [ ] **Step 1: Create `frontend/lib/bloc/trip/trip_event.dart`**

```dart
import 'package:equatable/equatable.dart';
import '../../models/person.dart';

abstract class TripEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AddStop extends TripEvent {
  final Person person;
  AddStop(this.person);
  @override
  List<Object?> get props => [person];
}

class RemoveStop extends TripEvent {
  final int index;
  RemoveStop(this.index);
  @override
  List<Object?> get props => [index];
}

class ReorderStops extends TripEvent {
  final int oldIndex;
  final int newIndex;
  ReorderStops(this.oldIndex, this.newIndex);
  @override
  List<Object?> get props => [oldIndex, newIndex];
}

class OptimizeTrip extends TripEvent {}
class ClearTrip extends TripEvent {}
```

- [ ] **Step 2: Create `frontend/lib/bloc/trip/trip_state.dart`**

```dart
import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../models/trip.dart';

class TripState extends Equatable {
  final List<TripStop> stops;
  final List<LatLng> routePoints;
  final bool isLoading;

  const TripState({
    this.stops = const [],
    this.routePoints = const [],
    this.isLoading = false,
  });

  TripState copyWith({
    List<TripStop>? stops,
    List<LatLng>? routePoints,
    bool? isLoading,
  }) {
    return TripState(
      stops: stops ?? this.stops,
      routePoints: routePoints ?? this.routePoints,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [stops, routePoints, isLoading];
}
```

- [ ] **Step 3: Create `frontend/lib/bloc/trip/trip_bloc.dart`**

Include the Multi-start Greedy TSP algorithm here.

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import '../../models/trip.dart';
import '../../services/routing_service.dart';
import 'trip_event.dart';
import 'trip_state.dart';

class TripBloc extends Bloc<TripEvent, TripState> {
  final RoutingService _routingService = RoutingService();

  TripBloc() : super(const TripState()) {
    on<AddStop>(_onAddStop);
    on<RemoveStop>(_onRemoveStop);
    on<ReorderStops>(_onReorderStops);
    on<ClearTrip>(_onClearTrip);
    on<OptimizeTrip>(_onOptimizeTrip);
  }

  Future<void> _onAddStop(AddStop event, Emitter<TripState> emit) async {
    if (event.person.latitude == null || event.person.longitude == null) return;
    
    final newStop = TripStop(
      id: DateTime.now().toString(),
      person: event.person,
      location: LatLng(event.person.latitude!, event.person.longitude!),
      sequenceOrder: state.stops.length,
    );
    
    final newStops = List<TripStop>.from(state.stops)..add(newStop);
    emit(state.copyWith(stops: newStops, isLoading: true));
    
    final route = await _routingService.getRoute(newStops.map((s) => s.location).toList());
    emit(state.copyWith(routePoints: route, isLoading: false));
  }

  Future<void> _onRemoveStop(RemoveStop event, Emitter<TripState> emit) async {
    final newStops = List<TripStop>.from(state.stops)..removeAt(event.index);
    emit(state.copyWith(stops: _resortStops(newStops), isLoading: true));
    
    final route = await _routingService.getRoute(newStops.map((s) => s.location).toList());
    emit(state.copyWith(routePoints: route, isLoading: false));
  }

  Future<void> _onReorderStops(ReorderStops event, Emitter<TripState> emit) async {
    var newStops = List<TripStop>.from(state.stops);
    int newIndex = event.newIndex;
    if (event.oldIndex < newIndex) newIndex -= 1;
    final item = newStops.removeAt(event.oldIndex);
    newStops.insert(newIndex, item);
    
    emit(state.copyWith(stops: _resortStops(newStops), isLoading: true));
    final route = await _routingService.getRoute(newStops.map((s) => s.location).toList());
    emit(state.copyWith(routePoints: route, isLoading: false));
  }

  void _onClearTrip(ClearTrip event, Emitter<TripState> emit) {
    emit(const TripState());
  }

  Future<void> _onOptimizeTrip(OptimizeTrip event, Emitter<TripState> emit) async {
    if (state.stops.length < 3) return;
    emit(state.copyWith(isLoading: true));
    
    final optimized = _solveTSP(state.stops);
    final route = await _routingService.getRoute(optimized.map((s) => s.location).toList());
    
    emit(state.copyWith(stops: _resortStops(optimized), routePoints: route, isLoading: false));
  }

  List<TripStop> _resortStops(List<TripStop> stops) {
    return List.generate(stops.length, (i) => stops[i].copyWith(sequenceOrder: i));
  }

  List<TripStop> _solveTSP(List<TripStop> stops) {
    List<TripStop>? bestPath;
    double minDistance = double.infinity;

    for (int start = 0; start < stops.length; start++) {
      final currentPath = _greedyPath(stops, start);
      final totalDist = _calculateTotalDistance(currentPath);
      if (totalDist < minDistance) {
        minDistance = totalDist;
        bestPath = currentPath;
      }
    }
    return bestPath ?? stops;
  }

  List<TripStop> _greedyPath(List<TripStop> stops, int startIndex) {
    final unvisited = List<TripStop>.from(stops);
    final path = <TripStop>[unvisited.removeAt(startIndex)];
    final distance = const Distance();

    while (unvisited.isNotEmpty) {
      int nearestIdx = 0;
      double minDist = double.infinity;
      for (int i = 0; i < unvisited.length; i++) {
        final d = distance.as(LengthUnit.Meter, path.last.location, unvisited[i].location);
        if (d < minDist) {
          minDist = d;
          nearestIdx = i;
        }
      }
      path.add(unvisited.removeAt(nearestIdx));
    }
    return path;
  }

  double _calculateTotalDistance(List<TripStop> path) {
    final distance = const Distance();
    double total = 0;
    for (int i = 0; i < path.length - 1; i++) {
      total += distance.as(LengthUnit.Meter, path[i].location, path[i + 1].location);
    }
    return total;
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/bloc/trip/
git commit -m "feat: implement TripBloc with multi-start greedy TSP"
```

---

## Task 4: Trip Planner UI

- [ ] **Step 1: Create `frontend/lib/screens/map/trip_planner_sheet.dart`**

```dart
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
      maxChildSize: 0.6,
      builder: (context, scrollController) {
        return BlocBuilder<TripBloc, TripState>(
          builder: (context, state) {
            return GlassContainer(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2))),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Trip Planner (${state.stops.length} stops)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        if (state.stops.length > 2)
                          TextButton.icon(
                            onPressed: () => context.read<TripBloc>().add(OptimizeTrip()),
                            icon: const Icon(Icons.auto_fix_high),
                            label: const Text('Optimize'),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: state.stops.isEmpty 
                      ? const Center(child: Text('Add friends from the map to start planning!'))
                      : ReorderableListView.builder(
                          scrollController: scrollController,
                          itemCount: state.stops.length,
                          itemBuilder: (context, index) {
                            final stop = state.stops[index];
                            return ListTile(
                              key: ValueKey(stop.id),
                              leading: CircleAvatar(child: Text(String.fromCharCode(65 + index))),
                              title: Text('${stop.person?.firstName} ${stop.person?.lastName}'),
                              trailing: const Icon(Icons.drag_handle),
                            );
                          },
                          onReorder: (oldIdx, newIdx) => context.read<TripBloc>().add(ReorderStops(oldIdx, newIdx)),
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
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/map/trip_planner_sheet.dart
git commit -m "feat: add Draggable TripPlannerSheet with ReorderableListView"
```

---

## Task 5: Map Integration

- [ ] **Step 1: Register TripBloc in `frontend/lib/main.dart`**

Wrap the root `MultiBlocProvider` to include `TripBloc`.

- [ ] **Step 2: Add PolylineLayer to `frontend/lib/screens/map/map_screen.dart`**

```dart
// inside FlutterMap children
BlocBuilder<TripBloc, TripState>(
  builder: (context, state) {
    return PolylineLayer(
      polylines: [
        Polyline(
          points: state.routePoints,
          color: Colors.indigo.withOpacity(0.7),
          strokeWidth: 5,
        ),
      ],
    );
  },
),
```

- [ ] **Step 3: Add Sequence Markers to `frontend/lib/screens/map/map_screen.dart`**

```dart
BlocBuilder<TripBloc, TripState>(
  builder: (context, state) {
    return MarkerLayer(
      markers: state.stops.asMap().entries.map((entry) {
        final idx = entry.key;
        final stop = entry.value;
        return Marker(
          point: stop.location,
          width: 30,
          height: 30,
          child: Container(
            decoration: const BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
            child: Center(child: Text(String.fromCharCode(65 + idx), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ),
        );
      }).toList(),
    );
  },
),
```

- [ ] **Step 4: Update `MapControls` to include a toggle for the planner.**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: integrate TripBloc and PolylineLayer into MapScreen"
```
