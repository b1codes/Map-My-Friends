# Historical Trip Details & Metadata Snapshotting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a detailed "Trip Details View" that displays a historical snapshot of a planned trip, ensuring data integrity by freezing metadata (names, addresses) upon booking.

**Architecture:** 
1. **Backend:** Update `TripStop` model to include snapshot fields and implement a `perform_snapshot()` trigger in `Trip.save()`.
2. **Frontend Models:** Update Dart models to support new snapshot fields and fallback logic.
3. **Frontend UI:** Build a dedicated `TripDetailsScreen` and update navigation logic in `TripsScreen`.

**Tech Stack:** Django 6.0, DRF, Flutter (BLoC), PostGIS.

---

### Task 1: Backend - Update Models & Snapshot Logic

**Files:**
- Modify: `backend/apps/trips/models.py`
- Test: `backend/apps/trips/tests.py`

- [ ] **Step 1: Add snapshot fields to TripStop**

```python
# backend/apps/trips/models.py
class TripStop(models.Model):
    # ... existing fields ...
    snapshot_address = models.CharField(max_length=500, null=True, blank=True)
    snapshot_metadata = models.JSONField(default=dict, blank=True)

    def perform_snapshot(self):
        """Captures metadata from linked people and hubs."""
        metadata = {
            "people": [{"id": p.id, "name": p.full_name} for p in self.people.all()],
            "hub": None
        }
        
        # Capture Address
        if self.people.exists():
            self.snapshot_address = self.people.first().current_address_string
        elif self.airport:
            self.snapshot_address = self.airport.address_string
            metadata["hub"] = {"name": self.airport.name, "code": self.airport.iata_code, "type": "AIRPORT"}
        elif self.station:
            self.snapshot_address = self.station.address_string
            metadata["hub"] = {"name": self.station.name, "code": self.station.code, "type": "STATION"}
            
        self.snapshot_metadata = metadata
        self.save()
```

- [ ] **Step 2: Implement Save Trigger in Trip Model**

```python
# backend/apps/trips/models.py
class Trip(models.Model):
    # ...
    def save(self, *args, **kwargs):
        is_new = self.pk is None
        old_status = None
        if not is_new:
            old_status = Trip.objects.get(pk=self.pk).status
        
        super().save(*args, **kwargs)
        
        # Transition from DRAFT to BOOKED
        if old_status == self.Status.DRAFT and self.status == self.Status.BOOKED:
            for stop in self.stops.all():
                stop.perform_snapshot()
```

- [ ] **Step 3: Write tests for snapshotting**

```python
# backend/apps/trips/tests.py
def test_trip_snapshot_on_booking(self):
    person = Person.objects.create(full_name="Original Name", current_address_string="123 Old St", ...)
    trip = Trip.objects.create(user=self.user, name="Snapshot Test", status=Trip.Status.DRAFT)
    stop = TripStop.objects.create(trip=trip, sequence_order=1, location=Point(0,0))
    stop.people.add(person)
    
    # Book the trip
    trip.status = Trip.Status.BOOKED
    trip.save()
    
    stop.refresh_from_db()
    assert stop.snapshot_address == "123 Old St"
    assert stop.snapshot_metadata["people"][0]["name"] == "Original Name"
    
    # Modify original person
    person.full_name = "New Name"
    person.save()
    
    stop.refresh_from_db()
    # Snapshot should remain unchanged
    assert stop.snapshot_metadata["people"][0]["name"] == "Original Name"
```

- [ ] **Step 4: Verify tests pass**

Run: `make test`

- [ ] **Step 5: Commit backend changes**

```bash
git add backend/apps/trips/models.py backend/apps/trips/tests.py
git commit -m "feat(backend): implement metadata snapshotting for booked trips"
```

---

### Task 2: Frontend - Update Models & Serializers

**Files:**
- Modify: `frontend/lib/models/trip.dart`
- Modify: `backend/apps/trips/serializers.py`

- [ ] **Step 1: Update TripStop fields in Dart**

```dart
// frontend/lib/models/trip.dart
class TripStop extends Equatable {
  // ...
  final String? snapshotAddress;
  final Map<String, dynamic>? snapshotMetadata;

  const TripStop({
    // ...
    this.snapshotAddress,
    this.snapshotMetadata,
  });
  
  // Update copyWith and fromJson
}
```

- [ ] **Step 2: Update TripStopSerializer in Django**

```python
# backend/apps/trips/serializers.py
class TripStopSerializer(serializers.ModelSerializer):
    # ...
    class Meta:
        model = TripStop
        fields = ('id', 'people', 'airport', 'station', 'sequence_order', 'location', 
                  'snapshot_address', 'snapshot_metadata')
```

- [ ] **Step 3: Commit model updates**

```bash
git add frontend/lib/models/trip.dart backend/apps/trips/serializers.py
git commit -m "feat: add snapshot fields to trip models and serializers"
```

---

### Task 3: Frontend - Create Trip Details Screen

**Files:**
- Create: `frontend/lib/screens/trips/trip_details_screen.dart`
- Modify: `frontend/lib/main.dart` (Add route)
- Modify: `frontend/lib/screens/trips/trips_screen.dart` (Add navigation)

- [ ] **Step 1: Implement TripDetailsScreen**

Create a screen that displays:
- Large header with Trip Name and Date.
- Map view (static or restricted interaction).
- List of stops using `GlassContainer` with snapshot data logic.

- [ ] **Step 2: Add navigation to TripsScreen**

Update the `onTap` or menu action for booked trips to navigate to `TripDetailsScreen` instead of switching planning modes.

- [ ] **Step 3: Verify navigation and display**

Run app, book a trip, and verify the Details view shows the correct snapshot data.

- [ ] **Step 4: Commit UI changes**

```bash
git add frontend/lib/screens/trips/trip_details_screen.dart frontend/lib/main.dart frontend/lib/screens/trips/trips_screen.dart
git commit -m "feat(frontend): implement TripDetailsScreen with snapshot data display"
```
