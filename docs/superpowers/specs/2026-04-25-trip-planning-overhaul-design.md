# Trip Planning Overhaul Design

**Date:** 2026-04-25
**Status:** Approved
**Scope:** Frontend (Flutter) UI/UX Refactor

## 1. Overview
The current vertical `TripPlannerSheet` (based on `DraggableScrollableSheet`) is being replaced with a more streamlined, horizontal "Trip Planning Mode". This mode activates automatically when the first stop is added to a trip and provides a compact, non-obstructive way to manage stops, save drafts, and clear the session.

## 2. Goals
- **Automatic Activation**: Remove the manual toggle for trip planning.
- **Improved Visibility**: Use a horizontal layout to preserve map space.
- **Efficient Actions**: Provide quick-access "Save as Draft" and "Clear" buttons.
- **Dynamic Layout**: Shift existing map controls (zoom, pan, etc.) upward when the modal is active.

## 3. Architecture & Components

### 3.1 `HorizontalTripPlanner` (New Component)
A new widget located in `lib/components/map/horizontal_trip_planner.dart`.
- **Layout**: Fixed-height (approx. 140px) `GlassContainer` anchored to the bottom.
- **Stops List**: A horizontal `ListView.builder`.
    - Each stop is a `StopCard` (Column-based for future expansion).
    - Displays sequence letter (A, B, C...) in a circle.
    - Displays Friend name or "Generic Stop".
- **Action Group**: Fixed `Padding` on the far right.
    - **Save Icon**: Triggers `SaveTrip` with `TripStatus.draft`.
    - **Clear Icon**: Triggers `ClearTrip` and exits planning mode.

### 3.2 `MapScreen` (Refactor)
- **Logic**: Use `BlocBuilder<TripBloc, TripState>` to detect if `state.stops.isNotEmpty`.
- **State**: Pass a `bool isTripPlanning` to `MapControls` and the new `HorizontalTripPlanner`.
- **Layers**: Ensure `HorizontalTripPlanner` is at the top of the stack.

### 3.3 `MapControls` (Refactor)
- **Animation**: Wrap control groups in `AnimatedPositioned`.
- **Shift**: When `isTripPlanning` is true, shift the `bottom` value of the controls group by +140px to float above the modal.

## 4. Data Flow
1. **Trigger**: User adds a friend/stop via `UnifiedClusterModal` or other interactions.
2. **State Update**: `TripBloc` adds the stop; `TripState.stops` is no longer empty.
3. **UI Response**: `MapScreen` detects the change, displays `HorizontalTripPlanner`, and signals `MapControls` to shift up.
4. **Action (Save)**: User taps Save. A default name is generated (e.g., "Draft Trip [Date]"). Trip is saved to DB with `draft` status.
5. **Action (Clear)**: User taps Clear. `TripBloc` clears stops; UI reverts to standard Map mode.

## 5. Visual Specifications
- **Modal Background**: 80% opacity Blur (Glassmorphism).
- **Stop Indicators**: Amber (`Colors.amber`) for person-linked stops, Indigo for others.
- **Control Animation**: 300ms `Curves.easeInOut`.

## 6. Testing Strategy
- **Widget Test**: Verify `HorizontalTripPlanner` appears when `TripState` has stops.
- **Widget Test**: Verify `MapControls` position changes based on the boolean flag.
- **Integration Test**: Add a stop -> Save -> Verify `SaveTrip` event is sent with correct parameters.
