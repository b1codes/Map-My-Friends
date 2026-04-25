# Trip Planning Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the vertical `TripPlannerSheet` with an automatic, horizontal `HorizontalTripPlanner` and animate `MapControls` to shift upward when planning is active.

**Architecture:** 
- `MapScreen` observes `TripBloc` state and conditionally displays `HorizontalTripPlanner`.
- `MapControls` uses `AnimatedPositioned` to float above the modal.
- `HorizontalTripPlanner` uses a horizontal `ListView` for stops and a fixed action bar.

**Tech Stack:** Flutter, BLoC (TripBloc), Glassmorphism (GlassContainer), flutter_map.

---

### Task 1: Update `MapControls` for Dynamic Positioning

**Files:**
- Modify: `frontend/lib/components/map/map_controls.dart`

- [ ] **Step 1: Update `MapControls` constructor to accept `isBottomModalVisible`**
Add the `final bool isBottomModalVisible;` parameter and update the constructor.

- [ ] **Step 2: Refactor Positioned to AnimatedPositioned**
Wrap the pan and zoom control groups in `AnimatedPositioned` with a 300ms duration and `Curves.easeInOut`.
Adjust the `bottom` value:
- Pan Controls: `isBottomModalVisible ? (isDesktop ? 160 : 260) : (isDesktop ? 20 : 120)`
- Zoom Controls: `isBottomModalVisible ? (isDesktop ? 320 : 420) : (isDesktop ? 180 : 280)`

- [ ] **Step 3: Commit**
```bash
git add frontend/lib/components/map/map_controls.dart
git commit -m "refactor(map): update map controls for dynamic positioning"
```

---

### Task 2: Create `HorizontalTripPlanner` Component

**Files:**
- Create: `frontend/lib/components/map/horizontal_trip_planner.dart`
- Create: `frontend/test/components/map/horizontal_trip_planner_test.dart`

- [ ] **Step 1: Implement the base widget and stop cards**
Implement `HorizontalTripPlanner` with a horizontal `ListView.builder` wrapped in a `GlassContainer`. Each stop should display its sequence letter in an Amber/Indigo circle and the name below it.

- [ ] **Step 2: Implement the Action Group**
Add a fixed vertical column on the right with a Save (Draft) and Clear button. Ensure the Save button defaults to `TripStatus.draft`.

- [ ] **Step 3: Write widget test**
Verify that the planner correctly renders the number of stops and handles the clear action.

- [ ] **Step 4: Commit**
```bash
git add frontend/lib/components/map/horizontal_trip_planner.dart frontend/test/components/map/horizontal_trip_planner_test.dart
git commit -m "feat(map): add horizontal trip planner component"
```

---

### Task 3: Refactor `MapScreen` Integration

**Files:**
- Modify: `frontend/lib/screens/map/map_screen.dart`

- [ ] **Step 1: Integrate HorizontalTripPlanner**
Replace the usage of `TripPlannerSheet` with `HorizontalTripPlanner`. Wrap the controls and planner in a `BlocBuilder<TripBloc, TripState>` to compute the `isBottomModalVisible` flag based on `state.stops.isNotEmpty`.

- [ ] **Step 2: Remove obsolete methods**
Remove `_toggleTripPlanner` and `_showTripPlanner` state if they are no longer used anywhere else (the overhaul makes the visibility automatic).

- [ ] **Step 3: Verify with static analysis**
Run `mcp_dart_analyze_files` to ensure no syntax or deprecation errors were introduced.

- [ ] **Step 4: Commit**
```bash
git add frontend/lib/screens/map/map_screen.dart
git commit -m "refactor(map): integrate horizontal trip planner and automatic controls shifting"
```
