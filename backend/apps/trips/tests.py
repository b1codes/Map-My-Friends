from django.contrib.auth.models import User
from django.test import SimpleTestCase
from rest_framework.test import APITestCase

from apps.common.testing import FirestoreTestMixin
from apps.trips.repositories import DuplicateSequenceOrder, TripRepository

TRIP_DATA = {
    "name": "Summer trip",
    "date": "2026-08-01",
    "start_date": "2026-08-01",
    "end_date": "2026-08-10",
    "status": "DRAFT",
}


class TripRepositoryTests(FirestoreTestMixin, SimpleTestCase):
    collections_to_purge = ["trips"]

    def setUp(self):
        super().setUp()
        self.trips = TripRepository()

    def test_create_assigns_string_id_and_owner(self):
        trip = self.trips.create("owner-a", TRIP_DATA)
        self.assertIsInstance(trip.id, str)
        self.assertEqual(trip.owner_key, "owner-a")

    def test_list_is_owner_scoped(self):
        self.trips.create("owner-a", TRIP_DATA)
        self.trips.create("owner-b", TRIP_DATA)
        self.assertEqual(len(self.trips.list_for_owner("owner-a")), 1)

    def test_get_for_wrong_owner_returns_none(self):
        trip = self.trips.create("owner-a", TRIP_DATA)
        self.assertIsNone(self.trips.get_for_owner(trip.id, "owner-b"))

    def test_dates_default_from_legacy_date_field(self):
        trip = self.trips.create(
            "owner-a", {"name": "T", "date": "2026-09-01", "status": "DRAFT"}
        )
        self.assertEqual(trip.start_date, "2026-09-01")
        self.assertEqual(trip.end_date, "2026-09-01")

    def test_add_stop_persists(self):
        trip = self.trips.create("owner-a", TRIP_DATA)
        stop = self.trips.add_stop(
            trip.id, "owner-a", {"sequence_order": 1, "lat": 1.0, "lng": 2.0}
        )
        self.assertEqual(stop.sequence_order, 1)

    def test_duplicate_sequence_order_rejected(self):
        trip = self.trips.create("owner-a", TRIP_DATA)
        self.trips.add_stop(
            trip.id, "owner-a", {"sequence_order": 1, "lat": 1.0, "lng": 2.0}
        )
        with self.assertRaises(DuplicateSequenceOrder):
            self.trips.add_stop(
                trip.id, "owner-a", {"sequence_order": 1, "lat": 3.0, "lng": 4.0}
            )

    def test_add_stop_for_wrong_owner_returns_none(self):
        trip = self.trips.create("owner-a", TRIP_DATA)
        self.assertIsNone(
            self.trips.add_stop(
                trip.id, "owner-b", {"sequence_order": 1, "lat": 1.0, "lng": 2.0}
            )
        )

    def test_add_stop_links_consecutive_stops(self):
        trip = self.trips.create("owner-a", TRIP_DATA)
        for order in (1, 2, 3):
            self.trips.add_stop(
                trip.id, "owner-a", {"sequence_order": order, "lat": 1.0, "lng": 2.0}
            )

        self.assertEqual(len(self.trips.list_legs(trip.id, "owner-a")), 2)

    def test_snapshot_on_draft_to_booked(self):
        trip = self.trips.create("owner-a", TRIP_DATA)
        self.trips.add_stop(
            trip.id,
            "owner-a",
            {"sequence_order": 1, "lat": 1.0, "lng": 2.0, "airport_id": 1},
        )
        self.trips.update(trip.id, "owner-a", {"status": "BOOKED"})

        stops = self.trips.list_stops(trip.id, "owner-a")
        self.assertTrue(stops[0].snapshot_address)
        self.assertIn("hub", stops[0].snapshot_metadata)

    def test_delete_removes_trip_and_children(self):
        trip = self.trips.create("owner-a", TRIP_DATA)
        self.trips.add_stop(
            trip.id, "owner-a", {"sequence_order": 1, "lat": 1.0, "lng": 2.0}
        )
        self.assertTrue(self.trips.delete(trip.id, "owner-a"))
        self.assertIsNone(self.trips.get_for_owner(trip.id, "owner-a"))

    def test_delete_by_wrong_owner_refused(self):
        trip = self.trips.create("owner-a", TRIP_DATA)
        self.assertFalse(self.trips.delete(trip.id, "owner-b"))


class TripEndpointTests(FirestoreTestMixin, APITestCase):
    collections_to_purge = ["trips"]

    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(username="owner-a", password="pw12345!")
        self.other = User.objects.create_user(username="owner-b", password="pw12345!")
        self.client.force_authenticate(user=self.user)

    def test_requires_authentication(self):
        self.client.force_authenticate(user=None)
        self.assertEqual(self.client.get("/api/trips/").status_code, 401)

    def test_create_and_list(self):
        created = self.client.post("/api/trips/", TRIP_DATA, format="json")
        self.assertEqual(created.status_code, 201)
        self.assertEqual(len(self.client.get("/api/trips/").data), 1)

    def test_trip_data_isolation(self):
        self.client.post("/api/trips/", TRIP_DATA, format="json")
        self.client.force_authenticate(user=self.other)
        self.assertEqual(len(self.client.get("/api/trips/").data), 0)

    def test_cannot_retrieve_another_owners_trip(self):
        created = self.client.post("/api/trips/", TRIP_DATA, format="json")
        self.client.force_authenticate(user=self.other)
        response = self.client.get(f"/api/trips/{created.data['id']}/")
        self.assertEqual(response.status_code, 404)

    def test_duplicate_sequence_order_returns_400(self):
        created = self.client.post("/api/trips/", TRIP_DATA, format="json")
        trip_id = created.data["id"]
        # `location` is required, so the payload must carry it — otherwise both
        # posts 400 on validation and never reach the DuplicateSequenceOrder
        # handler, making this assertion vacuous.
        stop = {
            "sequence_order": 1,
            "location": {"type": "Point", "coordinates": [2.0, 1.0]},
        }
        first = self.client.post(f"/api/trips/{trip_id}/stops/", stop, format="json")
        self.assertEqual(first.status_code, 201)

        second = self.client.post(f"/api/trips/{trip_id}/stops/", stop, format="json")
        self.assertEqual(second.status_code, 400)
        self.assertIn("sequence_order", second.data)


class TripNestedContractTests(FirestoreTestMixin, APITestCase):
    """Locks the payload shape Flutter's Trip.fromJson actually parses.

    trip.dart does `json['stops'] as List` with no null guard, and
    TripStop.fromJson reads json['location']['coordinates'] as [lng, lat].
    A flat trip payload, or flat lat/lng on a stop, breaks the Trips tab with
    a TypeError rather than a visible error — so these assertions mirror the
    client's parsing exactly.
    """

    collections_to_purge = ["trips"]

    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(username="owner-a", password="pw12345!")
        self.client.force_authenticate(user=self.user)
        self.payload = {
            "name": "Nested trip",
            "date": "2026-08-01",
            "stops": [
                {
                    "sequence_order": 0,
                    "location": {"type": "Point", "coordinates": [-87.6298, 41.8781]},
                },
                {
                    "sequence_order": 1,
                    "location": {"type": "Point", "coordinates": [-0.1278, 51.5074]},
                },
            ],
        }

    def test_create_persists_nested_stops(self):
        response = self.client.post("/api/trips/", self.payload, format="json")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(len(response.data["stops"]), 2)

    def test_response_always_carries_stops_and_legs_keys(self):
        self.client.post("/api/trips/", self.payload, format="json")
        listing = self.client.get("/api/trips/")
        self.assertEqual(listing.status_code, 200)
        for trip in listing.data:
            # `json['stops'] as List` throws on a missing key.
            self.assertIn("stops", trip)
            self.assertIn("legs", trip)
            self.assertIsInstance(trip["stops"], list)
            self.assertIsInstance(trip["legs"], list)

    def test_stop_location_is_geojson_point_lng_lat(self):
        created = self.client.post("/api/trips/", self.payload, format="json")
        stop = created.data["stops"][0]
        self.assertEqual(stop["location"]["type"], "Point")
        # [longitude, latitude] — reversing this silently misplaces the stop.
        self.assertEqual(stop["location"]["coordinates"], [-87.6298, 41.8781])

    def test_stops_are_ordered_by_sequence(self):
        created = self.client.post("/api/trips/", self.payload, format="json")
        orders = [s["sequence_order"] for s in created.data["stops"]]
        self.assertEqual(orders, sorted(orders))

    def test_legs_generated_between_consecutive_stops(self):
        created = self.client.post("/api/trips/", self.payload, format="json")
        self.assertEqual(len(created.data["legs"]), 1)

    def test_update_replaces_stops(self):
        created = self.client.post("/api/trips/", self.payload, format="json")
        trip_id = created.data["id"]

        response = self.client.patch(
            f"/api/trips/{trip_id}/",
            {
                "name": "Nested trip",
                "date": "2026-08-01",
                "stops": [
                    {
                        "sequence_order": 0,
                        "location": {"type": "Point", "coordinates": [2.3522, 48.8566]},
                    }
                ],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["stops"]), 1)
        self.assertEqual(
            response.data["stops"][0]["location"]["coordinates"], [2.3522, 48.8566]
        )

    def test_stop_without_location_is_rejected(self):
        response = self.client.post(
            "/api/trips/",
            {"name": "Bad", "date": "2026-08-01", "stops": [{"sequence_order": 0}]},
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    def test_reversed_coordinates_are_rejected(self):
        response = self.client.post(
            "/api/trips/",
            {
                "name": "Bad",
                "date": "2026-08-01",
                "stops": [
                    {
                        "sequence_order": 0,
                        # latitude in the longitude slot, out of range
                        "location": {"type": "Point", "coordinates": [41.8781, -187.0]},
                    }
                ],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)
