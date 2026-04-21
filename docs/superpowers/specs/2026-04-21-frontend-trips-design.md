# Frontend Trips Feature — Design Spec

**Date:** 2026-04-21
**Tasks:** 86b9gcuh8, 86b9gcuh7
**Status:** Approved

---

## Overview

Implement an interactive "Trip Builder" in the Flutter frontend. This allows users to select friends (stops), reorder them via drag-and-drop, optimize the route using a TSP approximation, and visualize the path on the map using a hybrid routing approach (roads for cars, straight lines for flights/trains).

---

## Architecture

### 1. State Management (`TripBloc`)
- **Location:** `frontend/lib/bloc/trip/`
- **State:** `TripState`
    - `List<TripStop> stops`: The ordered list of stops.
    - `List<LatLng> routePoints`: The coordinates for the Polyline.
    - `bool isOptimizing`: Loading state for TSP/Routing calculation.
- **Events:**
    - `AddStop(Person person)`: Adds a stop at the person's location.
    - `RemoveStop(int index)`
    - `ReorderStops(int oldIndex, int newIndex)`
    - `OptimizeTrip()`: Triggers the multi-start greedy TSP algorithm.
    - `FetchRoute()`: Calls the `RoutingService` to update `routePoints`.

### 2. Data Models (`frontend/lib/models/trip.dart`)
- `TripStop`: Represents a point in the trip.
    - `String id`
    - `Person? person` (optional if stop is a generic point)
    - `LatLng location`
    - `int sequenceOrder`

### 3. Services (`frontend/lib/services/routing_service.dart`)
- **Responsibility:** Interface with OSRM API for road routes.
- **Hybrid Logic:**
    - Segment Friend -> Friend: Request OSRM `v1/driving` route.
    - Segment involves Airport/Station: Return straight line (LatLng interpolation).
    - Fallback: Any OSRM failure defaults to straight line.

---

## UI Components

### 1. Trip Planner Sheet (`frontend/lib/screens/map/trip_planner_sheet.dart`)
- A `DraggableScrollableSheet` using `GlassContainer`.
- **Content:** `ReorderableListView` of stops.
- **Actions:** "Optimize" button, "Clear" button, and "Save Trip" button.

### 2. Map Integration (`frontend/lib/screens/map/map_screen.dart`)
- **PolylineLayer:** Displays the `routePoints` from `TripBloc`.
- **Sequence Markers:** A separate `MarkerLayer` showing 'A', 'B', 'C' labels at stop locations.
- **Toggle Button:** A new glass icon button in `MapControls` to expand/collapse the planner.

---

## Algorithms

### Optimization (TSP Approximation)
- **Algorithm:** Multi-start Greedy (Nearest Neighbor).
- **Implementation:**
    1. For every stop in the list, treat it as a potential "Start".
    2. Build a greedy path from that start by always picking the nearest unvisited stop.
    3. Calculate total distance for that path.
    4. Select the path with the minimum total distance.
- **Constraint:** Small stop count (< 10) ensures this is nearly instantaneous.

---

## Testing Strategy

- **Unit Tests:** `TripBloc` logic (adding/removing/reordering) and the TSP algorithm.
- **Widget Tests:** `TripPlannerSheet` drag-and-drop interaction.
- **Integration:** Mock OSRM API responses to verify polyline rendering.

---

## Out of Scope
- Turn-by-turn navigation instructions.
- Real-time GPS tracking along the route.
- Offline routing support.
