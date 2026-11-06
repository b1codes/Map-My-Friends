"""Firestore repositories for Trip and its stop/leg subcollections.

Layout:
    trips/{tripId}          owner_key: str
      ├── stops/{stopId}
      └── legs/{legId}

Firestore cannot express unique_together(trip, sequence_order), so add_stop
runs in a transaction that re-reads existing orders and refuses duplicates.
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass, field
from datetime import UTC, datetime

from google.cloud import firestore as gcloud_firestore

from apps.airports import reference as airport_reference
from apps.common import firestore as fs
from apps.stations import reference as station_reference

TRIPS = "trips"
STOPS = "stops"
LEGS = "legs"

STATUS_DRAFT = "DRAFT"
STATUS_BOOKED = "BOOKED"


class DuplicateSequenceOrder(Exception):
    """Raised when a stop would reuse an existing sequence_order on a trip."""


@dataclass
class TripRecord:
    id: str
    owner_key: str
    # Stops and legs are nested in the API payload (Flutter's Trip.fromJson
    # reads them inline), so hydrated trips carry them.
    stops: list = field(default_factory=list)
    legs: list = field(default_factory=list)
    name: str = ""
    date: str | None = None
    start_date: str | None = None
    end_date: str | None = None
    status: str = STATUS_DRAFT


@dataclass
class TripStopRecord:
    id: str
    trip_id: str
    sequence_order: int = 0
    lat: float | None = None
    lng: float | None = None
    person_ids: list[str] = field(default_factory=list)
    airport_id: int | None = None
    station_id: int | None = None
    snapshot_address: str = ""
    snapshot_metadata: dict = field(default_factory=dict)


@dataclass
class TripLegRecord:
    id: str
    trip_id: str
    departure_stop_id: str = ""
    arrival_stop_id: str = ""
    departure_time: str | None = None
    arrival_time: str | None = None
    transport_type: str = "CAR"
    booking_reference: str = ""
    ticket_data: dict = field(default_factory=dict)


def _now_iso() -> str:
    return datetime.now(UTC).isoformat()


class TripRepository:
    def _collection(self):
        return fs.collection(TRIPS)

    def _owned_ref(self, trip_id: str, owner_key: str):
        if not fs.is_valid_doc_id(trip_id):
            return None
        ref = self._collection().document(trip_id)
        doc = ref.get()
        if not doc.exists or (doc.to_dict() or {}).get("owner_key") != owner_key:
            return None
        return ref

    def _hydrate(self, doc, with_children: bool = True) -> TripRecord:
        data = doc.to_dict() or {}
        stops: list = []
        legs: list = []
        if with_children:
            stops = [
                self._hydrate_stop(d, doc.id)
                for d in doc.reference.collection(STOPS).stream()
            ]
            stops.sort(key=lambda s: s.sequence_order)
            legs = [
                self._hydrate_leg(d, doc.id)
                for d in doc.reference.collection(LEGS).stream()
            ]
        return TripRecord(
            id=doc.id,
            owner_key=data.get("owner_key", ""),
            stops=stops,
            legs=legs,
            name=data.get("name", ""),
            date=data.get("date"),
            start_date=data.get("start_date"),
            end_date=data.get("end_date"),
            status=data.get("status", STATUS_DRAFT),
        )

    def _hydrate_stop(self, doc, trip_id: str) -> TripStopRecord:
        data = doc.to_dict() or {}
        return TripStopRecord(
            id=doc.id,
            trip_id=trip_id,
            sequence_order=int(data.get("sequence_order", 0)),
            lat=data.get("lat"),
            lng=data.get("lng"),
            person_ids=list(data.get("person_ids", [])),
            airport_id=data.get("airport_id"),
            station_id=data.get("station_id"),
            snapshot_address=data.get("snapshot_address", ""),
            snapshot_metadata=dict(data.get("snapshot_metadata", {})),
        )

    def _hydrate_leg(self, doc, trip_id: str) -> TripLegRecord:
        data = doc.to_dict() or {}
        return TripLegRecord(
            id=doc.id,
            trip_id=trip_id,
            departure_stop_id=data.get("departure_stop_id", ""),
            arrival_stop_id=data.get("arrival_stop_id", ""),
            departure_time=data.get("departure_time"),
            arrival_time=data.get("arrival_time"),
            transport_type=data.get("transport_type", "CAR"),
            booking_reference=data.get("booking_reference", ""),
            ticket_data=dict(data.get("ticket_data", {})),
        )

    def list_for_owner(self, owner_key: str) -> list[TripRecord]:
        query = self._collection().where("owner_key", "==", owner_key)
        return [self._hydrate(doc) for doc in query.stream()]

    def get_for_owner(self, trip_id: str, owner_key: str) -> TripRecord | None:
        ref = self._owned_ref(trip_id, owner_key)
        return self._hydrate(ref.get()) if ref is not None else None

    def create(self, owner_key: str, data: dict) -> TripRecord:
        payload = {
            "owner_key": owner_key,
            "name": data.get("name", ""),
            "date": data.get("date"),
            # Sync start/end with the legacy `date` field when absent.
            "start_date": data.get("start_date") or data.get("date"),
            "end_date": data.get("end_date") or data.get("date"),
            "status": data.get("status", STATUS_DRAFT),
            "created_at": _now_iso(),
        }
        ref = self._collection().document()
        ref.set(payload)
        return self._hydrate(ref.get())

    def update(self, trip_id: str, owner_key: str, data: dict) -> TripRecord | None:
        ref = self._owned_ref(trip_id, owner_key)
        if ref is None:
            return None

        previous_status = (ref.get().to_dict() or {}).get("status", STATUS_DRAFT)
        payload = {
            k: v
            for k, v in data.items()
            if k in {"name", "date", "start_date", "end_date", "status"}
        }
        payload["updated_at"] = _now_iso()
        ref.update(payload)

        # Freeze stop snapshots on the DRAFT -> BOOKED transition.
        if previous_status == STATUS_DRAFT and payload.get("status") == STATUS_BOOKED:
            self.snapshot_stops(trip_id, owner_key)

        return self._hydrate(ref.get())

    def delete(self, trip_id: str, owner_key: str) -> bool:
        ref = self._owned_ref(trip_id, owner_key)
        if ref is None:
            return False
        for sub in (STOPS, LEGS):
            for doc in ref.collection(sub).stream():
                doc.reference.delete()
        ref.delete()
        return True

    def list_stops(self, trip_id: str, owner_key: str) -> list[TripStopRecord]:
        ref = self._owned_ref(trip_id, owner_key)
        if ref is None:
            return []
        stops = [
            self._hydrate_stop(doc, trip_id) for doc in ref.collection(STOPS).stream()
        ]
        stops.sort(key=lambda s: s.sequence_order)
        return stops

    def list_legs(self, trip_id: str, owner_key: str) -> list[TripLegRecord]:
        ref = self._owned_ref(trip_id, owner_key)
        if ref is None:
            return []
        return [
            self._hydrate_leg(doc, trip_id) for doc in ref.collection(LEGS).stream()
        ]

    def add_stop(
        self, trip_id: str, owner_key: str, data: dict
    ) -> TripStopRecord | None:
        trip_ref = self._owned_ref(trip_id, owner_key)
        if trip_ref is None:
            return None

        sequence_order = int(data.get("sequence_order", 0))
        stops_ref = trip_ref.collection(STOPS)
        new_ref = stops_ref.document()

        client = fs.get_client()

        @gcloud_firestore.transactional
        def _create(transaction):
            existing = stops_ref.where("sequence_order", "==", sequence_order).limit(1)
            if list(existing.stream(transaction=transaction)):
                raise DuplicateSequenceOrder(
                    f"sequence_order {sequence_order} already exists on trip {trip_id}"
                )
            transaction.set(
                new_ref,
                {
                    "sequence_order": sequence_order,
                    "lat": data.get("lat"),
                    "lng": data.get("lng"),
                    "person_ids": list(data.get("person_ids", [])),
                    "airport_id": data.get("airport_id"),
                    "station_id": data.get("station_id"),
                    "snapshot_address": data.get("snapshot_address", ""),
                    "snapshot_metadata": data.get("snapshot_metadata", {}),
                },
            )

        _create(client.transaction())
        self.generate_legs(trip_id, owner_key)
        return self._hydrate_stop(new_ref.get(), trip_id)

    def replace_stops(self, trip_id: str, owner_key: str, stops_data: list) -> bool:
        """Replace a trip's stops wholesale, mirroring the old nested update.

        The previous ModelSerializer deleted every stop and recreated them from
        the payload, so sequence_order collisions were impossible by
        construction. Same semantics here: clear first, then insert in the
        given order, then regenerate legs.
        """
        trip_ref = self._owned_ref(trip_id, owner_key)
        if trip_ref is None:
            return False

        stops_ref = trip_ref.collection(STOPS)

        # One batch, so a failure mid-way cannot leave the trip with its old
        # stops deleted and the new ones unwritten. The old code had this via
        # transaction.atomic(); issuing the deletes and sets as independent
        # writes would strand the trip with zero stops on any error.
        batch = fs.get_client().batch()
        for doc in stops_ref.stream():
            batch.delete(doc.reference)
        # Legs reference stop IDs that are about to disappear, so they go too;
        # generate_legs rebuilds them from the new stops.
        for doc in trip_ref.collection(LEGS).stream():
            batch.delete(doc.reference)

        for index, data in enumerate(stops_data):
            batch.set(
                stops_ref.document(),
                {
                    "sequence_order": int(data.get("sequence_order", index)),
                    "lat": data.get("lat"),
                    "lng": data.get("lng"),
                    "person_ids": list(data.get("person_ids", [])),
                    "airport_id": data.get("airport_id"),
                    "station_id": data.get("station_id"),
                    "snapshot_address": data.get("snapshot_address", ""),
                    "snapshot_metadata": data.get("snapshot_metadata", {}),
                },
            )
        batch.commit()

        self.generate_legs(trip_id, owner_key)
        return True

    def generate_legs(self, trip_id: str, owner_key: str) -> list[TripLegRecord]:
        """Ensure a leg exists between each consecutive pair of stops.

        Idempotent: existing pairs are left alone rather than recreated, so
        repeated calls do not duplicate legs or lose booking data.
        """
        trip_ref = self._owned_ref(trip_id, owner_key)
        if trip_ref is None:
            return []

        stops = self.list_stops(trip_id, owner_key)
        legs_ref = trip_ref.collection(LEGS)
        existing = {
            (
                (doc.to_dict() or {}).get("departure_stop_id"),
                (doc.to_dict() or {}).get("arrival_stop_id"),
            )
            for doc in legs_ref.stream()
        }

        for departure, arrival in itertools.pairwise(stops):
            if (departure.id, arrival.id) in existing:
                continue
            legs_ref.document().set(
                {
                    "departure_stop_id": departure.id,
                    "arrival_stop_id": arrival.id,
                    "departure_time": None,
                    "arrival_time": None,
                    "transport_type": "CAR",
                    "booking_reference": "",
                    "ticket_data": {},
                }
            )

        return self.list_legs(trip_id, owner_key)

    def update_leg(
        self, trip_id: str, leg_id: str, owner_key: str, data: dict
    ) -> TripLegRecord | None:
        trip_ref = self._owned_ref(trip_id, owner_key)
        if trip_ref is None or not fs.is_valid_doc_id(leg_id):
            return None
        leg_ref = trip_ref.collection(LEGS).document(leg_id)
        if not leg_ref.get().exists:
            return None
        leg_ref.update(data)
        return self._hydrate_leg(leg_ref.get(), trip_id)

    def snapshot_stops(self, trip_id: str, owner_key: str) -> None:
        """Freeze human-readable stop details at booking time.

        Mirrors the previous TripStop.perform_snapshot(), reading people from
        Firestore and hubs from the in-memory reference indexes.
        """
        from apps.people.repositories import PersonRepository

        trip_ref = self._owned_ref(trip_id, owner_key)
        if trip_ref is None:
            return

        people_repo = PersonRepository()
        for doc in trip_ref.collection(STOPS).stream():
            stop = self._hydrate_stop(doc, trip_id)
            metadata: dict = {"people": [], "hub": None}
            address_parts: list[str] = []

            for person_id in stop.person_ids:
                person = people_repo.get_for_owner(person_id, owner_key)
                if person is None:
                    continue
                full_name = f"{person.first_name} {person.last_name}".strip()
                metadata["people"].append({"id": person.id, "name": full_name})
                address_parts.append(
                    ", ".join(
                        filter(
                            None,
                            [
                                full_name,
                                person.street,
                                person.city,
                                person.state,
                                person.country,
                            ],
                        )
                    )
                )

            if stop.airport_id:
                airport = airport_reference.get_by_id(stop.airport_id)
                if airport is not None:
                    metadata["hub"] = {
                        "name": airport.name,
                        "code": airport.iata_code,
                        "type": "AIRPORT",
                    }
                    address_parts.append(f"{airport.name} ({airport.iata_code})")
            elif stop.station_id:
                station = station_reference.get_by_id(stop.station_id)
                if station is not None:
                    metadata["hub"] = {
                        "name": station.name,
                        "code": station.uic_ref or str(station.osm_id),
                        "type": "STATION",
                    }
                    address_parts.append(station.name)

            doc.reference.update(
                {
                    "snapshot_address": ", ".join(address_parts),
                    "snapshot_metadata": metadata,
                }
            )
