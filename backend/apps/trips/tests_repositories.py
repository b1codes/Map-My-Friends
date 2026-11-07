import dataclasses
import threading
from unittest.mock import patch

from django.test import SimpleTestCase

from apps.common.testing import FirestoreTestMixin
from apps.people.repositories import PersonRepository
from apps.stations import reference as station_reference
from apps.trips.repositories import DuplicateSequenceOrder, TripRepository

TRIP_DATA = {"name": "Summer trip", "date": "2026-08-01", "status": "DRAFT"}

HEATHROW_ID = 2159  # London Heathrow Airport (LHR) in airports_export.json
FIRST_STREET_ID = 1  # "1st Street", osm_id 17680222, no uic_ref
UNKNOWN_HUB_ID = 999_999_999


class TripRepositoryTestCase(FirestoreTestMixin, SimpleTestCase):
    collections_to_purge = ["trips", "people"]

    def setUp(self):
        super().setUp()
        self.trips = TripRepository()
        self.trip = self.trips.create("owner-a", TRIP_DATA)

    def add_stops(self, *stops, trip_id=None):
        self.trips.replace_stops(trip_id or self.trip.id, "owner-a", list(stops))
        return self.trips.list_stops(trip_id or self.trip.id, "owner-a")


class TripRepositoryOwnershipTests(TripRepositoryTestCase):
    """Every entry point refuses a trip the caller does not own, and none of
    them leaves a write behind when it does."""

    def test_update_by_wrong_owner_returns_none_and_writes_nothing(self):
        self.assertIsNone(self.trips.update(self.trip.id, "owner-b", {"name": "X"}))
        self.assertEqual(
            self.trips.get_for_owner(self.trip.id, "owner-a").name, "Summer trip"
        )

    def test_update_unknown_trip_returns_none(self):
        self.assertIsNone(self.trips.update("missing", "owner-a", {"name": "X"}))

    def test_children_hidden_from_wrong_owner(self):
        self.add_stops({"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0})
        self.assertEqual(self.trips.list_stops(self.trip.id, "owner-b"), [])
        self.assertEqual(self.trips.list_legs(self.trip.id, "owner-b"), [])
        self.assertEqual(self.trips.generate_legs(self.trip.id, "owner-b"), [])

    def test_replace_stops_by_wrong_owner_is_refused(self):
        self.add_stops({"lat": 1.0, "lng": 2.0})
        self.assertFalse(
            self.trips.replace_stops(
                self.trip.id, "owner-b", [{"lat": 9.0, "lng": 9.0}]
            )
        )
        stops = self.trips.list_stops(self.trip.id, "owner-a")
        self.assertEqual([(s.lat, s.lng) for s in stops], [(1.0, 2.0)])

    def test_update_leg_by_wrong_owner_is_refused(self):
        self.add_stops({"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0})
        leg = self.trips.list_legs(self.trip.id, "owner-a")[0]

        self.assertIsNone(
            self.trips.update_leg(
                self.trip.id, leg.id, "owner-b", {"booking_reference": "X"}
            )
        )
        self.assertEqual(
            self.trips.list_legs(self.trip.id, "owner-a")[0].booking_reference, ""
        )

    def test_snapshot_by_wrong_owner_is_a_no_op(self):
        self.add_stops({"lat": 1.0, "lng": 2.0, "airport_id": HEATHROW_ID})
        self.trips.snapshot_stops(self.trip.id, "owner-b")
        self.assertEqual(
            self.trips.list_stops(self.trip.id, "owner-a")[0].snapshot_address, ""
        )


class TripRepositoryUpdateTests(TripRepositoryTestCase):
    def test_update_ignores_non_writable_fields(self):
        updated = self.trips.update(
            self.trip.id,
            "owner-a",
            {"name": "Renamed", "owner_key": "owner-b", "stops": ["x"]},
        )
        self.assertEqual(updated.name, "Renamed")
        self.assertEqual(updated.owner_key, "owner-a")
        self.assertIsNotNone(self.trips.get_for_owner(self.trip.id, "owner-a"))

    def test_rebooking_does_not_refresh_snapshots(self):
        # Snapshots freeze on the DRAFT -> BOOKED transition only, so a later
        # write that repeats BOOKED must not overwrite what was frozen.
        self.add_stops({"lat": 1.0, "lng": 2.0, "airport_id": HEATHROW_ID})
        self.trips.update(self.trip.id, "owner-a", {"status": "BOOKED"})
        stop = self.trips.list_stops(self.trip.id, "owner-a")[0]

        with patch.object(TripRepository, "_stop_snapshots") as mock_snapshot:
            self.trips.update(self.trip.id, "owner-a", {"status": "BOOKED"})
            self.trips.update(self.trip.id, "owner-a", {"status": "CANCELLED"})
        mock_snapshot.assert_not_called()
        self.assertEqual(
            self.trips.list_stops(self.trip.id, "owner-a")[0].snapshot_address,
            stop.snapshot_address,
        )


class TripRepositoryStopTests(TripRepositoryTestCase):
    def test_replace_stops_defaults_order_to_position(self):
        stops = self.add_stops({"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0})
        self.assertEqual([s.sequence_order for s in stops], [0, 1])

    def test_replace_stops_rebuilds_legs_for_new_stops(self):
        self.add_stops({"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0})
        old_leg = self.trips.list_legs(self.trip.id, "owner-a")[0]

        stops = self.add_stops(
            {"lat": 5.0, "lng": 6.0}, {"lat": 7.0, "lng": 8.0}, {"lat": 9.0, "lng": 9.5}
        )
        legs = self.trips.list_legs(self.trip.id, "owner-a")
        self.assertEqual(len(legs), 2)
        self.assertNotIn(old_leg.id, [leg.id for leg in legs])
        stop_ids = {s.id for s in stops}
        for leg in legs:
            self.assertIn(leg.departure_stop_id, stop_ids)
            self.assertIn(leg.arrival_stop_id, stop_ids)

    def test_generate_legs_preserves_existing_booking_data(self):
        self.add_stops({"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0})
        booked = self.trips.list_legs(self.trip.id, "owner-a")[0]
        self.trips.update_leg(
            self.trip.id, booked.id, "owner-a", {"booking_reference": "BA123"}
        )

        legs = self.trips.generate_legs(self.trip.id, "owner-a")
        self.assertEqual(
            [(leg.id, leg.booking_reference) for leg in legs], [(booked.id, "BA123")]
        )

    def test_stop_without_coordinates_hydrates_with_none(self):
        self.trips.add_stop(self.trip.id, "owner-a", {"sequence_order": 0})
        stop = self.trips.list_stops(self.trip.id, "owner-a")[0]
        self.assertIsNone(stop.lat)
        self.assertIsNone(stop.lng)
        self.assertEqual(stop.person_ids, [])


class TripRepositoryUpdateLegTests(TripRepositoryTestCase):
    def setUp(self):
        super().setUp()
        self.add_stops({"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0})
        self.leg = self.trips.list_legs(self.trip.id, "owner-a")[0]

    def test_update_leg_merges_fields(self):
        updated = self.trips.update_leg(
            self.trip.id,
            self.leg.id,
            "owner-a",
            {"transport_type": "FLIGHT", "ticket_data": {"seat": "1A"}},
        )
        self.assertEqual(updated.id, self.leg.id)
        self.assertEqual(updated.transport_type, "FLIGHT")
        self.assertEqual(updated.ticket_data, {"seat": "1A"})
        self.assertEqual(updated.departure_stop_id, self.leg.departure_stop_id)

    def test_update_unknown_leg_returns_none_without_creating_it(self):
        self.assertIsNone(
            self.trips.update_leg(
                self.trip.id, "missing", "owner-a", {"booking_reference": "X"}
            )
        )
        self.assertEqual(
            [leg.id for leg in self.trips.list_legs(self.trip.id, "owner-a")],
            [self.leg.id],
        )


class TripRepositorySnapshotTests(TripRepositoryTestCase):
    def setUp(self):
        super().setUp()
        self.people = PersonRepository()

    def snapshot(self, *stops):
        self.add_stops(*stops)
        self.trips.snapshot_stops(self.trip.id, "owner-a")
        return self.trips.list_stops(self.trip.id, "owner-a")

    def test_people_and_airport_build_address_and_metadata(self):
        ada = self.people.create(
            "owner-a",
            {
                "first_name": "Ada",
                "last_name": "Lovelace",
                "street": "12 St James's Square",
                "city": "London",
                "state": "",
                "country": "UK",
            },
        )
        cher = self.people.create("owner-a", {"first_name": "Cher", "city": "LA"})

        stop = self.snapshot(
            {
                "lat": 51.47,
                "lng": -0.45,
                "person_ids": [ada.id, cher.id],
                "airport_id": HEATHROW_ID,
            }
        )[0]

        self.assertEqual(
            stop.snapshot_address,
            "Ada Lovelace, 12 St James's Square, London, UK, "
            "Cher, LA, "
            "London Heathrow Airport (LHR)",
        )
        self.assertEqual(
            stop.snapshot_metadata,
            {
                "people": [
                    {"id": ada.id, "name": "Ada Lovelace"},
                    {"id": cher.id, "name": "Cher"},
                ],
                "hub": {
                    "name": "London Heathrow Airport",
                    "code": "LHR",
                    "type": "AIRPORT",
                },
            },
        )

    def test_missing_and_foreign_people_are_skipped(self):
        theirs = self.people.create(
            "owner-b", {"first_name": "Not", "last_name": "Mine"}
        )

        stop = self.snapshot(
            {"lat": 1.0, "lng": 2.0, "person_ids": ["deleted-person", theirs.id]}
        )[0]
        self.assertEqual(stop.snapshot_address, "")
        self.assertEqual(stop.snapshot_metadata, {"people": [], "hub": None})

    def test_station_hub_falls_back_to_osm_id_code(self):
        stop = self.snapshot({"lat": 1.0, "lng": 2.0, "station_id": FIRST_STREET_ID})[0]
        self.assertEqual(stop.snapshot_address, "1st Street")
        self.assertEqual(
            stop.snapshot_metadata["hub"],
            {"name": "1st Street", "code": "17680222", "type": "STATION"},
        )

    def test_station_hub_prefers_uic_ref(self):
        # The bundled dataset has no station with a uic_ref, so give one.
        station = dataclasses.replace(
            station_reference.get_by_id(FIRST_STREET_ID), uic_ref="8000105"
        )
        with patch(
            "apps.trips.repositories.station_reference.get_by_id",
            return_value=station,
        ):
            stop = self.snapshot(
                {"lat": 1.0, "lng": 2.0, "station_id": FIRST_STREET_ID}
            )[0]
        self.assertEqual(stop.snapshot_metadata["hub"]["code"], "8000105")

    def test_airport_takes_precedence_over_station(self):
        stop = self.snapshot(
            {
                "lat": 1.0,
                "lng": 2.0,
                "airport_id": HEATHROW_ID,
                "station_id": FIRST_STREET_ID,
            }
        )[0]
        self.assertEqual(stop.snapshot_metadata["hub"]["type"], "AIRPORT")
        self.assertEqual(stop.snapshot_address, "London Heathrow Airport (LHR)")

    def test_unknown_hubs_leave_hub_empty(self):
        stops = self.snapshot(
            {"sequence_order": 0, "lat": 1.0, "lng": 2.0, "airport_id": UNKNOWN_HUB_ID},
            {"sequence_order": 1, "lat": 3.0, "lng": 4.0, "station_id": UNKNOWN_HUB_ID},
            {"sequence_order": 2, "lat": 5.0, "lng": 6.0},
        )
        for stop in stops:
            with self.subTest(stop.sequence_order):
                self.assertEqual(stop.snapshot_address, "")
                self.assertEqual(stop.snapshot_metadata, {"people": [], "hub": None})


class TripRepositoryBatchedReadTests(TripRepositoryTestCase):
    """Lists read every trip's stops and legs in one query per collection,
    so they have to be put back on the right trips."""

    def test_list_puts_each_trips_stops_and_legs_on_it_in_order(self):
        other = self.trips.create("owner-a", {"name": "Other", "date": "2026-09-01"})
        self.add_stops(
            {"sequence_order": 1, "lat": 3.0, "lng": 4.0},
            {"sequence_order": 0, "lat": 1.0, "lng": 2.0},
        )
        self.add_stops(
            {"lat": 5.0, "lng": 6.0},
            {"lat": 7.0, "lng": 8.0},
            {"lat": 9.0, "lng": 9.5},
            trip_id=other.id,
        )
        someone_elses = self.trips.create("owner-b", TRIP_DATA)
        self.trips.replace_stops(
            someone_elses.id,
            "owner-b",
            [{"lat": 0.5, "lng": 0.5}, {"lat": 1, "lng": 1}],
        )

        listed = {trip.id: trip for trip in self.trips.list_for_owner("owner-a")}

        self.assertEqual(sorted(listed), sorted([self.trip.id, other.id]))
        for trip_id, coords in {
            self.trip.id: [(1.0, 2.0), (3.0, 4.0)],
            other.id: [(5.0, 6.0), (7.0, 8.0), (9.0, 9.5)],
        }.items():
            with self.subTest(trip=trip_id):
                trip = listed[trip_id]
                self.assertEqual([(s.lat, s.lng) for s in trip.stops], coords)
                self.assertEqual(
                    trip, self.trips.get_for_owner(trip_id, "owner-a"), "list != get"
                )
                stop_ids = {s.id for s in trip.stops}
                self.assertEqual(len(trip.legs), len(coords) - 1)
                for leg in trip.legs:
                    self.assertEqual(leg.trip_id, trip_id)
                    self.assertIn(leg.departure_stop_id, stop_ids)

    def test_find_leg_and_list_all_legs_cover_every_trip_and_only_the_owners(self):
        other = self.trips.create("owner-a", {"name": "Other", "date": "2026-09-01"})
        self.add_stops({"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0})
        self.add_stops(
            {"lat": 5.0, "lng": 6.0}, {"lat": 7.0, "lng": 8.0}, trip_id=other.id
        )
        theirs = self.trips.create("owner-b", TRIP_DATA)
        self.trips.replace_stops(
            theirs.id, "owner-b", [{"lat": 0.5, "lng": 0.5}, {"lat": 1, "lng": 1}]
        )
        (their_leg,) = self.trips.list_legs(theirs.id, "owner-b")

        legs = self.trips.list_all_legs("owner-a")
        self.assertEqual(
            sorted(leg.trip_id for leg in legs), sorted([self.trip.id, other.id])
        )
        for leg in legs:
            self.assertEqual(self.trips.find_leg(leg.id, "owner-a"), leg)
        self.assertIsNone(self.trips.find_leg(their_leg.id, "owner-a"))


class TripRepositoryAtomicWriteTests(TripRepositoryTestCase):
    def test_create_with_stops_writes_trip_stops_and_legs_together(self):
        trip = self.trips.create(
            "owner-a",
            TRIP_DATA,
            stops=[{"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0}],
        )
        self.assertEqual(trip, self.trips.get_for_owner(trip.id, "owner-a"))
        self.assertEqual(len(trip.stops), 2)
        self.assertEqual(len(trip.legs), 1)

    def test_update_returns_what_a_fresh_read_returns(self):
        self.add_stops({"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0})
        (leg,) = self.trips.list_legs(self.trip.id, "owner-a")

        updated = self.trips.update(
            self.trip.id,
            "owner-a",
            {"name": "Renamed"},
            legs=[(leg.id, {"booking_reference": "BA123", "transport_type": "FLIGHT"})],
        )

        self.assertEqual(updated, self.trips.get_for_owner(self.trip.id, "owner-a"))
        self.assertEqual(updated.legs[0].booking_reference, "BA123")

    def test_leg_patches_naming_replaced_legs_are_dropped(self):
        self.add_stops({"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0})
        (old_leg,) = self.trips.list_legs(self.trip.id, "owner-a")

        updated = self.trips.update(
            self.trip.id,
            "owner-a",
            {},
            stops=[{"lat": 5.0, "lng": 6.0}, {"lat": 7.0, "lng": 8.0}],
            legs=[(old_leg.id, {"booking_reference": "LOST"})],
        )

        self.assertEqual([leg.booking_reference for leg in updated.legs], [""])
        self.assertNotIn(old_leg.id, [leg.id for leg in updated.legs])
        self.assertEqual(updated, self.trips.get_for_owner(self.trip.id, "owner-a"))

    def test_booking_with_new_stops_snapshots_the_new_stops(self):
        self.add_stops({"lat": 1.0, "lng": 2.0, "airport_id": HEATHROW_ID})

        booked = self.trips.update(
            self.trip.id,
            "owner-a",
            {"status": "BOOKED"},
            stops=[{"lat": 51.47, "lng": -0.45, "airport_id": HEATHROW_ID}],
        )

        (stop,) = self.trips.list_stops(self.trip.id, "owner-a")
        self.assertIn("(LHR)", stop.snapshot_address)
        self.assertEqual(booked.stops, [stop])

    def test_stops_added_at_once_never_share_an_order(self):
        """add_stop checks for a duplicate order in a transaction, so of
        several requests for the same order exactly one wins."""
        start = threading.Barrier(5)
        outcomes = []

        def add():
            start.wait()
            try:
                self.trips.add_stop(
                    self.trip.id, "owner-a", {"sequence_order": 3, "lat": 1, "lng": 2}
                )
                outcomes.append("added")
            except DuplicateSequenceOrder:
                outcomes.append("duplicate")

        threads = [threading.Thread(target=add) for _ in range(5)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertEqual(sorted(outcomes), ["added"] + ["duplicate"] * 4)
        self.assertEqual(len(self.trips.list_stops(self.trip.id, "owner-a")), 1)


class TripRepositoryInvalidIdTests(TripRepositoryTestCase):
    """Ids Firestore would reject, or that would address another path, can't
    name a trip or leg, so they read as not found without a round trip."""

    def test_unusable_ids_are_not_found(self):
        for bad in ("", "__reserved__", "a/b", ".."):
            with self.subTest(id=bad):
                self.assertEqual(self.trips.list_stops(bad, "owner-a"), [])
                self.assertEqual(self.trips.list_legs(bad, "owner-a"), [])
                self.assertIsNone(self.trips.find_leg(bad, "owner-a"))
                self.assertIsNone(self.trips.add_stop(bad, "owner-a", {"lat": 1}))
                self.assertIsNone(
                    self.trips.update_leg(
                        bad, "leg", "owner-a", {"booking_reference": "X"}
                    )
                )
                self.assertIsNone(
                    self.trips.update_leg(
                        self.trip.id, bad, "owner-a", {"booking_reference": "X"}
                    )
                )
