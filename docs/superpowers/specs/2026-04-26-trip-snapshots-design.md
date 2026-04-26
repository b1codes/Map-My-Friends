# Design Spec: Historical Trip Details & Metadata Snapshotting

**Date:** 2026-04-26
**Status:** Draft
**Goal:** Implement a "frozen" historical view for booked trips to ensure data integrity over time.

## 1. Problem Statement
Currently, `TripStop` objects link directly to `Person`, `Airport`, and `Station` models. If a user changes a friend's address or a station is renamed, historical trips are altered or potentially broken. We need a "Data Snapshot" that captures the state of the world at the moment a trip is booked.

## 2. Proposed Architecture

### 2.1 Backend (Django)
We will add snapshot fields to the `TripStop` model and implement a "Freeze" trigger in the `Trip` model.

**Model Changes (`backend/apps/trips/models.py`):**
- `TripStop.snapshot_address`: `CharField(max_length=500, null=True, blank=True)`
- `TripStop.snapshot_metadata`: `JSONField(default=dict, blank=True)`
    - Format: 
      ```json
      {
        "people": [{"id": 1, "name": "Sarah Jenkins"}],
        "hub": {"name": "SFO Airport", "code": "SFO", "type": "AIRPORT"}
      }
      ```

**Freeze Logic:**
- Override `Trip.save()` to detect a status transition from `DRAFT` to `BOOKED`.
- When triggered, iterate through all `stops` and call `stop.perform_snapshot()`.
- `perform_snapshot()` will:
    1. Capture the current `address_string` from all linked people or the linked hub.
    2. Serialize names and identifiers into the JSON field.

### 2.2 Frontend (Flutter)
The frontend will adapt its models and UI to prioritize snapshot data when available.

**Model Changes (`frontend/lib/models/trip.dart`):**
- Add `snapshotAddress` and `snapshotMetadata` to `TripStop`.
- Update `TripStop.fromJson` to handle these new fields.

**UI Implementation:**
- **New Screen:** `TripDetailsScreen` (`frontend/lib/screens/trips/trip_details_screen.dart`).
- **Behavior:**
    - If `Trip.status == BOOKED`, the UI displays text from `snapshotMetadata` and `snapshotAddress`.
    - Interactive "Live" links (e.g., "View Profile") will still point to the current `Person.id`, allowing the user to see the friend's *current* status while reading the *historical* context.
- **Visuals:**
    - Timeline view of stops.
    - Integrated map showing the route (geographic data is already "snapshotted" as the `location` PointField on the stop).

## 3. Data Flow
1. User plans a trip (Status: `DRAFT`). Stops show live data.
2. User clicks "Confirm/Book".
3. Backend receives `status: BOOKED`.
4. Backend triggers `perform_snapshot()` for all stops.
5. Frontend refreshes and displays the frozen metadata.

## 4. Testing & Validation
- **Unit Test (Backend):** Verify `perform_snapshot()` correctly captures data.
- **Integration Test:** Create trip -> Move person (change address) -> Book trip -> Verify snapshot contains the *original* address.
- **UI Test:** Ensure `TripDetailsScreen` renders correctly with both snapshot and fallback live data.

## 5. Security & Privacy
- Snapshots will contain PII (Names/Addresses). They will inherit the same access controls as the `Trip` model (only accessible by the trip owner).
