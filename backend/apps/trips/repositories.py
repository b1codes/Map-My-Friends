"""Firestore repositories for Trip and its stop/leg subcollections.

Layout:
    trips/{tripId}          owner_key: str
      ├── stops/{stopId}    owner_key: the trip's owner
      └── legs/{legId}      owner_key, leg_id: the trip's owner and the
                            document's own id

The copies of owner_key let one collection-group query fetch every stop or
leg an owner has, or one leg by id, instead of a query per trip. Every
request costs a fixed number of round trips, whatever the size of the
account (tests/test_round_trip_budgets.py), so a trip's writes go in one
commit and its reads in one query per collection.

Firestore cannot express unique_together(trip, sequence_order), so add_stop
runs in a transaction that re-reads existing orders and refuses duplicates.
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass, field, fields, replace
from datetime import UTC, datetime

from google.cloud.firestore_v1.base_query import FieldFilter

from apps.airports import reference as airport_reference
from apps.common import firestore as fs
from apps.stations import reference as station_reference

TRIPS = "trips"
STOPS = "stops"
LEGS = "legs"

STATUS_DRAFT = "DRAFT"
STATUS_BOOKED = "BOOKED"

_TRIP_WRITABLE = {"name", "date", "start_date", "end_date", "status"}


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


def _stop_payload(data: dict, index: int, owner_key: str) -> dict:
    return {
        "owner_key": owner_key,
        "sequence_order": int(data.get("sequence_order", index)),
        "lat": data.get("lat"),
        "lng": data.get("lng"),
        "person_ids": list(data.get("person_ids", [])),
        "airport_id": data.get("airport_id"),
        "station_id": data.get("station_id"),
        "snapshot_address": data.get("snapshot_address", "") or "",
        "snapshot_metadata": data.get("snapshot_metadata", {}) or {},
    }


def _hydrate_stop(stop_id: str, trip_id: str, data: dict) -> TripStopRecord:
    return TripStopRecord(
        id=stop_id,
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


def _hydrate_leg(leg_id: str, trip_id: str, data: dict) -> TripLegRecord:
    return TripLegRecord(
        id=leg_id,
        trip_id=trip_id,
        departure_stop_id=data.get("departure_stop_id", ""),
        arrival_stop_id=data.get("arrival_stop_id", ""),
        departure_time=data.get("departure_time"),
        arrival_time=data.get("arrival_time"),
        transport_type=data.get("transport_type", "CAR"),
        booking_reference=data.get("booking_reference", ""),
        ticket_data=dict(data.get("ticket_data", {})),
    )


_LEG_FIELDS = {f.name for f in fields(TripLegRecord)} - {"id", "trip_id"}


def _patched(leg: TripLegRecord, data: dict) -> TripLegRecord:
    """The leg with data's fields applied, as it is once data is written."""
    return replace(leg, **{k: v for k, v in data.items() if k in _LEG_FIELDS})


def _parent_id(doc) -> str:
    """The id of the trip a stop or leg document belongs to."""
    return doc.reference.parent.parent.id


class _TripWrite:
    """The writes for one trip, gathered so they go in a single commit and
    the result can be returned without reading it back."""

    def __init__(self, trip_ref, owner_key: str, stops: list, legs: list):
        self.trip_ref = trip_ref
        self.owner_key = owner_key
        self.stops = stops
        self.legs = legs
        self.batch = fs.get_client().batch()

    def replace_stops(self, stops_data: list) -> None:
        """Replace every stop, and every leg (they name the old stops' ids),
        then add a leg between each consecutive pair of new stops."""
        for record in self.stops:
            self.batch.delete(self.trip_ref.collection(STOPS).document(record.id))
        for record in self.legs:
            self.batch.delete(self.trip_ref.collection(LEGS).document(record.id))
        self.stops, self.legs = [], []
        for index, data in enumerate(stops_data):
            ref = self.trip_ref.collection(STOPS).document()
            payload = _stop_payload(data, index, self.owner_key)
            self.batch.set(ref, payload)
            self.stops.append(_hydrate_stop(ref.id, self.trip_ref.id, payload))
        self.stops.sort(key=lambda s: s.sequence_order)
        self.add_missing_legs()

    def add_missing_legs(self) -> None:
        """Ensure a leg exists between each consecutive pair of stops.

        Existing pairs are left alone rather than recreated, so booking data
        on them survives."""
        existing = {(leg.departure_stop_id, leg.arrival_stop_id) for leg in self.legs}
        for departure, arrival in itertools.pairwise(self.stops):
            if (departure.id, arrival.id) in existing:
                continue
            ref = self.trip_ref.collection(LEGS).document()
            payload = {
                "owner_key": self.owner_key,
                "leg_id": ref.id,
                "departure_stop_id": departure.id,
                "arrival_stop_id": arrival.id,
                "departure_time": None,
                "arrival_time": None,
                "transport_type": "CAR",
                "booking_reference": "",
                "ticket_data": {},
            }
            self.batch.set(ref, payload)
            self.legs.append(_hydrate_leg(ref.id, self.trip_ref.id, payload))

    def patch_leg(self, leg_id: str, data: dict) -> TripLegRecord | None:
        for index, leg in enumerate(self.legs):
            if leg.id == leg_id:
                self.batch.update(self.trip_ref.collection(LEGS).document(leg_id), data)
                self.legs[index] = _patched(leg, data)
                return self.legs[index]
        return None

    def snapshot(self, snapshots: dict) -> None:
        """Apply each stop's snapshot, from a dict holding one per stop."""
        for index, stop in enumerate(self.stops):
            change = snapshots[stop.id]
            self.batch.update(self.trip_ref.collection(STOPS).document(stop.id), change)
            self.stops[index] = replace(stop, **change)

    def commit(self) -> None:
        self.batch.commit()


class TripRepository:
    def _collection(self):
        return fs.collection(TRIPS)

    def _owned_doc(self, trip_id: str, owner_key: str):
        """The trip's snapshot if owner_key owns it, else None."""
        if not fs.is_valid_doc_id(trip_id):
            return None
        doc = self._collection().document(trip_id).get()
        if not doc.exists or (doc.to_dict() or {}).get("owner_key") != owner_key:
            return None
        return doc

    @staticmethod
    def _owned(trip_ref, sub: str, owner_key: str):
        return trip_ref.collection(sub).where(
            filter=FieldFilter("owner_key", "==", owner_key)
        )

    def _children(self, trip_ref, owner_key: str) -> tuple[list, list]:
        stops = [
            _hydrate_stop(d.id, trip_ref.id, d.to_dict() or {})
            for d in self._owned(trip_ref, STOPS, owner_key).stream()
        ]
        stops.sort(key=lambda s: s.sequence_order)
        legs = [
            _hydrate_leg(d.id, trip_ref.id, d.to_dict() or {})
            for d in self._owned(trip_ref, LEGS, owner_key).stream()
        ]
        return stops, legs

    @staticmethod
    def _record(trip_id: str, data: dict, stops=(), legs=()) -> TripRecord:
        return TripRecord(
            id=trip_id,
            owner_key=data.get("owner_key", ""),
            stops=list(stops),
            legs=list(legs),
            name=data.get("name", ""),
            date=data.get("date"),
            start_date=data.get("start_date"),
            end_date=data.get("end_date"),
            status=data.get("status", STATUS_DRAFT),
        )

    @staticmethod
    def _group(owner_key: str, sub: str):
        return (
            fs.get_client()
            .collection_group(sub)
            .where(filter=FieldFilter("owner_key", "==", owner_key))
        )

    def _start_write(self, trip_id: str, owner_key: str) -> tuple | None:
        doc = self._owned_doc(trip_id, owner_key)
        if doc is None:
            return None
        stops, legs = self._children(doc.reference, owner_key)
        return doc, _TripWrite(doc.reference, owner_key, stops, legs)

    def list_for_owner(self, owner_key: str) -> list[TripRecord]:
        trips = list(
            self._collection()
            .where(filter=FieldFilter("owner_key", "==", owner_key))
            .stream()
        )
        if not trips:
            return []
        stops: dict[str, list] = {}
        for doc in self._group(owner_key, STOPS).stream():
            trip_id = _parent_id(doc)
            stops.setdefault(trip_id, []).append(
                _hydrate_stop(doc.id, trip_id, doc.to_dict() or {})
            )
        legs: dict[str, list] = {}
        for doc in self._group(owner_key, LEGS).stream():
            trip_id = _parent_id(doc)
            legs.setdefault(trip_id, []).append(
                _hydrate_leg(doc.id, trip_id, doc.to_dict() or {})
            )
        return [
            self._record(
                doc.id,
                doc.to_dict() or {},
                sorted(stops.get(doc.id, []), key=lambda s: s.sequence_order),
                legs.get(doc.id, []),
            )
            for doc in trips
        ]

    def get_for_owner(self, trip_id: str, owner_key: str) -> TripRecord | None:
        doc = self._owned_doc(trip_id, owner_key)
        if doc is None:
            return None
        stops, legs = self._children(doc.reference, owner_key)
        return self._record(doc.id, doc.to_dict() or {}, stops, legs)

    def create(self, owner_key: str, data: dict, stops=None) -> TripRecord:
        """Create a trip, and its stops and legs if given, in one commit."""
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
        write = _TripWrite(self._collection().document(), owner_key, [], [])
        write.batch.set(write.trip_ref, payload)
        if stops:
            write.replace_stops(stops)
        write.commit()
        return self._record(write.trip_ref.id, payload, write.stops, write.legs)

    def update(
        self, trip_id: str, owner_key: str, data: dict, stops=None, legs=None
    ) -> TripRecord | None:
        """Update a trip in one commit.

        stops, when given, replaces the trip's stops wholesale (and so its
        legs). legs is a list of (leg id, fields) patches, applied to the legs
        as they are after that, so a patch naming a replaced leg is dropped.
        """
        started = self._start_write(trip_id, owner_key)
        if started is None:
            return None
        doc, write = started

        current = doc.to_dict() or {}
        payload = {k: v for k, v in data.items() if k in _TRIP_WRITABLE}
        payload["updated_at"] = _now_iso()
        write.batch.update(doc.reference, payload)
        if stops is not None:
            write.replace_stops(stops)
        for leg_id, changes in legs or ():
            write.patch_leg(leg_id, changes)

        # Freeze stop snapshots on the DRAFT -> BOOKED transition.
        previous_status = current.get("status", STATUS_DRAFT)
        if previous_status == STATUS_DRAFT and payload.get("status") == STATUS_BOOKED:
            write.snapshot(self._stop_snapshots(write.stops, owner_key))

        write.commit()
        return self._record(doc.id, {**current, **payload}, write.stops, write.legs)

    def delete(self, trip_id: str, owner_key: str) -> bool:
        doc = self._owned_doc(trip_id, owner_key)
        if doc is None:
            return False
        # Firestore leaves subcollections behind when a parent is deleted.
        children = [
            d.reference
            for sub in (STOPS, LEGS)
            for d in doc.reference.collection(sub).stream()
        ]
        fs.delete_all([*children, doc.reference])
        return True

    def list_stops(self, trip_id: str, owner_key: str) -> list[TripStopRecord]:
        """The trip's stops in order, or [] if owner_key doesn't own it.

        The stops carry their trip's owner, so this needs no read of the trip.
        """
        if not fs.is_valid_doc_id(trip_id):
            return []
        trip_ref = self._collection().document(trip_id)
        stops = [
            _hydrate_stop(d.id, trip_id, d.to_dict() or {})
            for d in self._owned(trip_ref, STOPS, owner_key).stream()
        ]
        stops.sort(key=lambda s: s.sequence_order)
        return stops

    def list_legs(self, trip_id: str, owner_key: str) -> list[TripLegRecord]:
        if not fs.is_valid_doc_id(trip_id):
            return []
        trip_ref = self._collection().document(trip_id)
        return [
            _hydrate_leg(d.id, trip_id, d.to_dict() or {})
            for d in self._owned(trip_ref, LEGS, owner_key).stream()
        ]

    def list_all_legs(self, owner_key: str) -> list[TripLegRecord]:
        """Every leg of every trip owner_key owns, in one query."""
        return [
            _hydrate_leg(d.id, _parent_id(d), d.to_dict() or {})
            for d in self._group(owner_key, LEGS).stream()
        ]

    def find_leg(self, leg_id: str, owner_key: str) -> TripLegRecord | None:
        """The owner's leg with this id, whichever trip it's on."""
        if not fs.is_valid_doc_id(leg_id):
            return None
        query = self._group(owner_key, LEGS).where(
            filter=FieldFilter("leg_id", "==", leg_id)
        )
        docs = list(query.limit(1).stream())
        if not docs:
            return None
        return _hydrate_leg(docs[0].id, _parent_id(docs[0]), docs[0].to_dict() or {})

    def add_stop(
        self, trip_id: str, owner_key: str, data: dict
    ) -> TripStopRecord | None:
        if not fs.is_valid_doc_id(trip_id):
            return None
        trip_ref = self._collection().document(trip_id)
        sequence_order = int(data.get("sequence_order", 0))
        new_ref = trip_ref.collection(STOPS).document()
        payload = _stop_payload(
            {**data, "sequence_order": sequence_order}, 0, owner_key
        )

        def create(transaction) -> TripStopRecord | None:
            trip = trip_ref.get(transaction=transaction)
            if not trip.exists or (trip.to_dict() or {}).get("owner_key") != owner_key:
                return None
            stops = [
                _hydrate_stop(d.id, trip_id, d.to_dict() or {})
                for d in trip_ref.collection(STOPS).stream(transaction=transaction)
            ]
            if any(stop.sequence_order == sequence_order for stop in stops):
                raise DuplicateSequenceOrder(
                    f"sequence_order {sequence_order} already exists on trip {trip_id}"
                )
            legs = [
                _hydrate_leg(d.id, trip_id, d.to_dict() or {})
                for d in trip_ref.collection(LEGS).stream(transaction=transaction)
            ]
            stop = _hydrate_stop(new_ref.id, trip_id, payload)
            write = _TripWrite(trip_ref, owner_key, [*stops, stop], legs)
            write.stops.sort(key=lambda s: s.sequence_order)
            # The transaction's writes, not a batch: they commit with it, and
            # only if nothing it read has changed.
            write.batch = transaction
            transaction.set(new_ref, payload)
            write.add_missing_legs()
            return stop

        return fs.run_transaction(create)

    def replace_stops(self, trip_id: str, owner_key: str, stops_data: list) -> bool:
        """Replace a trip's stops wholesale, and so its legs, in one commit.

        One commit, so a failure mid-way cannot leave the trip with its old
        stops deleted and the new ones unwritten.
        """
        started = self._start_write(trip_id, owner_key)
        if started is None:
            return False
        _doc, write = started
        write.replace_stops(stops_data)
        write.commit()
        return True

    def generate_legs(self, trip_id: str, owner_key: str) -> list[TripLegRecord]:
        """Ensure a leg exists between each consecutive pair of stops.

        Idempotent: existing pairs are left alone rather than recreated, so
        repeated calls do not duplicate legs or lose booking data.
        """
        started = self._start_write(trip_id, owner_key)
        if started is None:
            return []
        _doc, write = started
        write.add_missing_legs()
        write.commit()
        return write.legs

    def update_leg(
        self, trip_id: str, leg_id: str, owner_key: str, data: dict
    ) -> TripLegRecord | None:
        if not fs.is_valid_doc_id(trip_id) or not fs.is_valid_doc_id(leg_id):
            return None
        leg_ref = self._collection().document(trip_id).collection(LEGS).document(leg_id)
        doc = leg_ref.get()
        if not doc.exists or (doc.to_dict() or {}).get("owner_key") != owner_key:
            return None
        leg = _hydrate_leg(leg_id, trip_id, doc.to_dict() or {})
        return self.patch_leg(leg, data)

    def patch_leg(self, leg: TripLegRecord, data: dict) -> TripLegRecord:
        """Write data to a leg the caller has already found as its owner's,
        and return it as it now is."""
        self._collection().document(leg.trip_id).collection(LEGS).document(
            leg.id
        ).update(data)
        return _patched(leg, data)

    def snapshot_stops(self, trip_id: str, owner_key: str) -> None:
        """Freeze human-readable stop details now, as booking does."""
        started = self._start_write(trip_id, owner_key)
        if started is None:
            return
        _doc, write = started
        write.snapshot(self._stop_snapshots(write.stops, owner_key))
        write.commit()

    @staticmethod
    def _stop_snapshots(stops, owner_key: str) -> dict[str, dict]:
        """Each stop's frozen address and metadata, by stop id.

        Mirrors the previous TripStop.perform_snapshot(), reading the people
        in one batch and hubs from the in-memory reference indexes.
        """
        from apps.people.repositories import PersonRepository

        people = PersonRepository().get_many_for_owner(
            [person_id for stop in stops for person_id in stop.person_ids], owner_key
        )
        snapshots = {}
        for stop in stops:
            metadata: dict = {"people": [], "hub": None}
            address_parts: list[str] = []

            for person_id in stop.person_ids:
                person = people.get(person_id)
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

            snapshots[stop.id] = {
                "snapshot_address": ", ".join(address_parts),
                "snapshot_metadata": metadata,
            }
        return snapshots
