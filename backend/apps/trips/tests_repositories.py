import dataclasses
from unittest.mock import patch

from django.test import SimpleTestCase

from apps.common.testing import FirestoreTestMixin
from apps.people.repositories import PersonRepository
from apps.stations import reference as station_reference
from apps.trips.repositories import TripRepository

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

        with patch.object(TripRepository, "snapshot_stops") as mock_snapshot:
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
