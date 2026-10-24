from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

from django.contrib.auth.models import User
from rest_framework.test import APITestCase

from apps.common import firestore as fs
from apps.common.testing import FirestoreTestMixin
from apps.trips.repositories import TripRepository

TRIPS_URL = "/api/trips/"
LEGS_URL = "/api/trips/legs/"
ROUTE_URL = "/api/trips/calculate_route/"


def point(lng, lat):
    return {"type": "Point", "coordinates": [lng, lat]}


def stop(order, lng=0.0, lat=0.0, **extra):
    return {"sequence_order": order, "location": point(lng, lat), **extra}


CHICAGO = (-87.6298, 41.8781)
LONDON = (-0.1278, 51.5074)
PARIS = (2.3522, 48.8566)


class TripViewTestCase(FirestoreTestMixin, APITestCase):
    collections_to_purge = ["trips", "people"]

    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(username="owner-a", password="pw12345!")
        self.other = User.objects.create_user(username="owner-b", password="pw12345!")
        self.client.force_authenticate(user=self.user)
        self.trips = TripRepository()

    def create_trip(self, **overrides):
        payload = {"name": "Summer trip", "date": "2026-08-01", **overrides}
        response = self.client.post(TRIPS_URL, payload, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        return response.data

    def create_trip_with_stops(self, *coords):
        return self.create_trip(
            stops=[stop(i, lng, lat) for i, (lng, lat) in enumerate(coords)]
        )

    def raw_leg(self, trip_id, leg_id):
        """The leg document as Firestore holds it, bypassing the serializer."""
        return (
            fs.collection("trips")
            .document(trip_id)
            .collection("legs")
            .document(leg_id)
            .get()
            .to_dict()
        )


class TripListRetrieveTests(TripViewTestCase):
    def test_list_is_empty_for_new_user(self):
        response = self.client.get(TRIPS_URL)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, [])

    def test_list_returns_only_own_trips_with_children(self):
        self.create_trip_with_stops(CHICAGO, LONDON)
        self.trips.create("owner-b", {"name": "Not mine", "date": "2026-08-01"})

        response = self.client.get(TRIPS_URL)
        self.assertEqual(response.status_code, 200)
        self.assertEqual([t["name"] for t in response.data], ["Summer trip"])
        self.assertEqual(len(response.data[0]["stops"]), 2)
        self.assertEqual(len(response.data[0]["legs"]), 1)

    def test_retrieve_returns_full_representation(self):
        created = self.create_trip(start_date="2026-08-02", end_date="2026-08-09")

        response = self.client.get(f"{TRIPS_URL}{created['id']}/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.data,
            {
                "id": created["id"],
                "name": "Summer trip",
                "date": "2026-08-01",
                "start_date": "2026-08-02",
                "end_date": "2026-08-09",
                "status": "DRAFT",
                "user": "owner-a",
                "stops": [],
                "legs": [],
            },
        )

    def test_retrieve_unknown_trip_returns_404(self):
        response = self.client.get(f"{TRIPS_URL}does-not-exist/")
        self.assertEqual(response.status_code, 404)


class TripCreateTests(TripViewTestCase):
    def test_create_persists_trip_for_requesting_user(self):
        created = self.create_trip(status="BOOKED")

        trip = self.trips.get_for_owner(created["id"], "owner-a")
        self.assertIsNotNone(trip)
        self.assertEqual(trip.name, "Summer trip")
        self.assertEqual(trip.status, "BOOKED")
        self.assertEqual(created["user"], "owner-a")

    def test_status_defaults_to_draft(self):
        self.assertEqual(self.create_trip()["status"], "DRAFT")

    def test_start_and_end_default_to_legacy_date(self):
        created = self.create_trip(start_date=None)
        self.assertEqual(created["start_date"], "2026-08-01")
        self.assertEqual(created["end_date"], "2026-08-01")

    def test_missing_required_fields_returns_400(self):
        response = self.client.post(TRIPS_URL, {}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("name", response.data)
        self.assertIn("date", response.data)
        self.assertEqual(self.trips.list_for_owner("owner-a"), [])

    def test_invalid_status_returns_400(self):
        response = self.client.post(
            TRIPS_URL,
            {"name": "T", "date": "2026-08-01", "status": "SHIPPED"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("status", response.data)

    def test_malformed_date_returns_400(self):
        response = self.client.post(
            TRIPS_URL, {"name": "T", "date": "01/08/2026"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("date", response.data)

    def test_overlong_name_returns_400(self):
        response = self.client.post(
            TRIPS_URL, {"name": "x" * 256, "date": "2026-08-01"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("name", response.data)

    def test_nested_stop_carries_people_and_hubs(self):
        created = self.create_trip(
            stops=[stop(0, *CHICAGO, people=["p1", "p2"], airport=2159, station=1)]
        )
        stop_data = created["stops"][0]
        self.assertEqual(stop_data["people"], ["p1", "p2"])
        self.assertEqual(stop_data["airport"], 2159)
        self.assertEqual(stop_data["station"], 1)
        self.assertEqual(stop_data["trip"], created["id"])

    def test_supplied_legs_are_ignored_in_favour_of_generated_ones(self):
        # Legs only exist between stops, so create derives them rather than
        # trusting the client to send a consistent set.
        created = self.create_trip(
            stops=[stop(0, *CHICAGO), stop(1, *LONDON)],
            legs=[{"transport_type": "FLIGHT"}, {"transport_type": "TRAIN"}],
        )
        self.assertEqual(len(created["legs"]), 1)
        self.assertEqual(created["legs"][0]["transport_type"], "CAR")

    def test_invalid_nested_stop_rejects_whole_trip(self):
        response = self.client.post(
            TRIPS_URL,
            {
                "name": "Bad",
                "date": "2026-08-01",
                "stops": [stop(0, *CHICAGO), {"sequence_order": -1, "location": {}}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("stops", response.data)
        self.assertEqual(self.trips.list_for_owner("owner-a"), [])


class TripUpdateTests(TripViewTestCase):
    def test_put_replaces_trip_fields(self):
        created = self.create_trip()

        response = self.client.put(
            f"{TRIPS_URL}{created['id']}/",
            {
                "name": "Renamed",
                "date": "2026-09-01",
                "start_date": "2026-09-01",
                "end_date": "2026-09-05",
                "status": "CANCELLED",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["name"], "Renamed")
        self.assertEqual(response.data["end_date"], "2026-09-05")

        trip = self.trips.get_for_owner(created["id"], "owner-a")
        self.assertEqual(trip.name, "Renamed")
        self.assertEqual(trip.date, "2026-09-01")
        self.assertEqual(trip.status, "CANCELLED")

    def test_put_requires_full_payload(self):
        created = self.create_trip()
        response = self.client.put(
            f"{TRIPS_URL}{created['id']}/", {"name": "Only name"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("date", response.data)
        self.assertEqual(
            self.trips.get_for_owner(created["id"], "owner-a").name, "Summer trip"
        )

    def test_put_without_stops_leaves_stops_untouched(self):
        created = self.create_trip_with_stops(CHICAGO, LONDON)
        response = self.client.put(
            f"{TRIPS_URL}{created['id']}/",
            {"name": "Renamed", "date": "2026-08-01"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            [s["id"] for s in response.data["stops"]],
            [s["id"] for s in created["stops"]],
        )

    def test_put_unknown_trip_returns_404(self):
        response = self.client.put(
            f"{TRIPS_URL}does-not-exist/",
            {"name": "T", "date": "2026-08-01"},
            format="json",
        )
        self.assertEqual(response.status_code, 404)

    def test_patch_changes_only_supplied_fields(self):
        created = self.create_trip(end_date="2026-08-10")

        response = self.client.patch(
            f"{TRIPS_URL}{created['id']}/", {"name": "Renamed"}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["name"], "Renamed")
        self.assertEqual(response.data["date"], "2026-08-01")
        self.assertEqual(response.data["end_date"], "2026-08-10")

    def test_patch_unknown_trip_returns_404(self):
        response = self.client.patch(
            f"{TRIPS_URL}does-not-exist/", {"name": "Renamed"}, format="json"
        )
        self.assertEqual(response.status_code, 404)

    def test_patch_invalid_status_returns_400(self):
        created = self.create_trip()
        response = self.client.patch(
            f"{TRIPS_URL}{created['id']}/", {"status": "SHIPPED"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("status", response.data)

    def test_patch_with_empty_stops_clears_stops_and_legs(self):
        created = self.create_trip_with_stops(CHICAGO, LONDON)

        response = self.client.patch(
            f"{TRIPS_URL}{created['id']}/", {"stops": []}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["stops"], [])
        self.assertEqual(response.data["legs"], [])
        self.assertEqual(self.trips.list_stops(created["id"], "owner-a"), [])
        self.assertEqual(self.trips.list_legs(created["id"], "owner-a"), [])

    def test_patch_stop_without_location_is_rejected(self):
        # On PATCH DRF skips required=True for nested fields, so the stop
        # serializer enforces `location` itself; a stop without coordinates
        # would come back as location: null and break the Flutter client.
        created = self.create_trip_with_stops(CHICAGO)

        response = self.client.patch(
            f"{TRIPS_URL}{created['id']}/",
            {"stops": [{"sequence_order": 0}]},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data["stops"][0]["location"], ["This field is required."]
        )
        self.assertEqual(len(self.trips.list_stops(created["id"], "owner-a")), 1)

    def test_patch_legs_updates_existing_leg_by_id(self):
        created = self.create_trip_with_stops(CHICAGO, LONDON)
        leg_id = created["legs"][0]["id"]

        response = self.client.patch(
            f"{TRIPS_URL}{created['id']}/",
            {
                "legs": [
                    {
                        "id": leg_id,
                        "transport_type": "FLIGHT",
                        "booking_reference": "BA123",
                        "departure_time": "2026-08-01T10:00:00Z",
                    }
                ]
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        leg = response.data["legs"][0]
        self.assertEqual(leg["id"], leg_id)
        self.assertEqual(leg["transport_type"], "FLIGHT")
        self.assertEqual(leg["booking_reference"], "BA123")

        raw = self.raw_leg(created["id"], leg_id)
        self.assertEqual(
            datetime.fromisoformat(raw["departure_time"]),
            datetime(2026, 8, 1, 10, 0, tzinfo=UTC),
        )
        # The id addresses the leg; it must not be written into the document.
        self.assertNotIn("id", raw)
        # Stop links are derived from the stops and stay as generated.
        self.assertEqual(raw["departure_stop_id"], created["stops"][0]["id"])
        self.assertEqual(raw["arrival_stop_id"], created["stops"][1]["id"])

    def test_patch_legs_skips_entries_without_id_or_changes(self):
        created = self.create_trip_with_stops(CHICAGO, LONDON)
        leg_id = created["legs"][0]["id"]

        response = self.client.patch(
            f"{TRIPS_URL}{created['id']}/",
            {"legs": [{"booking_reference": "ORPHAN"}, {"id": leg_id}]},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["legs"]), 1)
        self.assertEqual(response.data["legs"][0]["booking_reference"], "")

    def test_patch_legs_with_unknown_id_is_ignored(self):
        created = self.create_trip_with_stops(CHICAGO, LONDON)

        response = self.client.patch(
            f"{TRIPS_URL}{created['id']}/",
            {"legs": [{"id": "not-a-leg", "booking_reference": "X"}]},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["legs"][0]["booking_reference"], "")
        self.assertEqual(len(self.trips.list_legs(created["id"], "owner-a")), 1)

    def test_patch_invalid_leg_returns_400(self):
        created = self.create_trip_with_stops(CHICAGO, LONDON)
        leg_id = created["legs"][0]["id"]

        response = self.client.patch(
            f"{TRIPS_URL}{created['id']}/",
            {"legs": [{"id": leg_id, "transport_type": "BOAT"}]},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("transport_type", response.data["legs"][0])
        self.assertEqual(
            self.trips.list_legs(created["id"], "owner-a")[0].transport_type, "CAR"
        )

    def test_booking_trip_freezes_stop_snapshots(self):
        created = self.create_trip(stops=[stop(0, *LONDON, airport=2159)])

        response = self.client.patch(
            f"{TRIPS_URL}{created['id']}/", {"status": "BOOKED"}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        snapshot = response.data["stops"][0]
        self.assertEqual(snapshot["snapshot_address"], "London Heathrow Airport (LHR)")
        self.assertEqual(
            snapshot["snapshot_metadata"]["hub"],
            {"name": "London Heathrow Airport", "code": "LHR", "type": "AIRPORT"},
        )

    def test_snapshot_fields_are_read_only(self):
        created = self.create_trip(
            stops=[
                stop(
                    0,
                    *LONDON,
                    snapshot_address="forged",
                    snapshot_metadata={"forged": True},
                )
            ]
        )
        self.assertEqual(created["stops"][0]["snapshot_address"], "")
        self.assertEqual(created["stops"][0]["snapshot_metadata"], {})


class TripDestroyTests(TripViewTestCase):
    def test_delete_removes_trip_and_subcollections(self):
        created = self.create_trip_with_stops(CHICAGO, LONDON)
        trip_ref = fs.collection("trips").document(created["id"])

        response = self.client.delete(f"{TRIPS_URL}{created['id']}/")
        self.assertEqual(response.status_code, 204)
        self.assertFalse(trip_ref.get().exists)
        self.assertEqual(list(trip_ref.collection("stops").stream()), [])
        self.assertEqual(list(trip_ref.collection("legs").stream()), [])
        self.assertEqual(
            self.client.get(f"{TRIPS_URL}{created['id']}/").status_code, 404
        )

    def test_delete_unknown_trip_returns_404(self):
        response = self.client.delete(f"{TRIPS_URL}does-not-exist/")
        self.assertEqual(response.status_code, 404)

    def test_second_delete_returns_404(self):
        created = self.create_trip()
        self.client.delete(f"{TRIPS_URL}{created['id']}/")
        response = self.client.delete(f"{TRIPS_URL}{created['id']}/")
        self.assertEqual(response.status_code, 404)


class TripStopsActionTests(TripViewTestCase):
    def stops_url(self, trip_id):
        return f"{TRIPS_URL}{trip_id}/stops/"

    def test_get_lists_stops_in_sequence_order(self):
        created = self.create_trip()
        for order, coords in ((2, PARIS), (0, CHICAGO), (1, LONDON)):
            self.client.post(
                self.stops_url(created["id"]), stop(order, *coords), format="json"
            )

        response = self.client.get(self.stops_url(created["id"]))
        self.assertEqual(response.status_code, 200)
        self.assertEqual([s["sequence_order"] for s in response.data], [0, 1, 2])
        self.assertEqual(response.data[0]["location"], point(*CHICAGO))

    def test_post_creates_stop_and_returns_it(self):
        created = self.create_trip()

        response = self.client.post(
            self.stops_url(created["id"]),
            stop(0, *PARIS, people=["p1"], station=1),
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["trip"], created["id"])
        self.assertEqual(response.data["location"], point(*PARIS))
        self.assertEqual(response.data["people"], ["p1"])
        self.assertEqual(response.data["station"], 1)
        self.assertIsNone(response.data["airport"])

        persisted = self.trips.list_stops(created["id"], "owner-a")
        self.assertEqual([s.id for s in persisted], [response.data["id"]])
        self.assertEqual((persisted[0].lng, persisted[0].lat), PARIS)

    def test_post_second_stop_generates_leg(self):
        created = self.create_trip()
        first = self.client.post(
            self.stops_url(created["id"]), stop(0, *CHICAGO), format="json"
        )
        second = self.client.post(
            self.stops_url(created["id"]), stop(1, *LONDON), format="json"
        )

        legs = self.client.get(f"{TRIPS_URL}{created['id']}/").data["legs"]
        self.assertEqual(len(legs), 1)
        self.assertEqual(legs[0]["departure_stop"], first.data["id"])
        self.assertEqual(legs[0]["arrival_stop"], second.data["id"])

    def test_post_to_unknown_trip_returns_404(self):
        response = self.client.post(
            self.stops_url("does-not-exist"), stop(0, *CHICAGO), format="json"
        )
        self.assertEqual(response.status_code, 404)

    def test_post_to_another_owners_trip_returns_404(self):
        trip = self.trips.create("owner-b", {"name": "Theirs", "date": "2026-08-01"})
        response = self.client.post(
            self.stops_url(trip.id), stop(0, *CHICAGO), format="json"
        )
        self.assertEqual(response.status_code, 404)
        self.assertEqual(self.trips.list_stops(trip.id, "owner-b"), [])

    def test_post_validation_errors_return_400(self):
        created = self.create_trip()
        cases = {
            "missing location": ({"sequence_order": 0}, "location"),
            "negative order": (stop(-1, *CHICAGO), "sequence_order"),
            "location not an object": (
                {"sequence_order": 0, "location": "41.8,-87.6"},
                "location",
            ),
            "bad coordinate count": (
                {"sequence_order": 0, "location": {"coordinates": [1.0]}},
                "location",
            ),
            "non-numeric coordinate": (
                {"sequence_order": 0, "location": {"coordinates": ["a", "b"]}},
                "location",
            ),
            "non-integer airport": (stop(0, *CHICAGO, airport="LHR"), "airport"),
        }
        for label, (payload, field) in cases.items():
            with self.subTest(label):
                response = self.client.post(
                    self.stops_url(created["id"]), payload, format="json"
                )
                self.assertEqual(response.status_code, 400)
                self.assertIn(field, response.data)
        self.assertEqual(self.trips.list_stops(created["id"], "owner-a"), [])

    def test_duplicate_sequence_order_leaves_single_stop(self):
        created = self.create_trip()
        self.client.post(
            self.stops_url(created["id"]), stop(0, *CHICAGO), format="json"
        )

        response = self.client.post(
            self.stops_url(created["id"]), stop(0, *LONDON), format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("already exists", response.data["sequence_order"][0])

        stops = self.trips.list_stops(created["id"], "owner-a")
        self.assertEqual(len(stops), 1)
        self.assertEqual((stops[0].lng, stops[0].lat), CHICAGO)

    def test_stops_action_rejects_other_methods(self):
        created = self.create_trip()
        response = self.client.delete(self.stops_url(created["id"]))
        self.assertEqual(response.status_code, 405)


class CalculateRouteTests(TripViewTestCase):
    GEOMETRY = {"type": "LineString", "coordinates": [[-87.6, 41.8], [-0.1, 51.5]]}

    def osrm_response(self, body):
        response = MagicMock()
        response.json.return_value = body
        response.raise_for_status.return_value = None
        return response

    def test_invalid_payloads_return_400(self):
        cases = {
            "missing": ({}, 'Missing or invalid "coordinates"'),
            "empty": ({"coordinates": []}, 'Missing or invalid "coordinates"'),
            "not a list": (
                {"coordinates": "1,2;3,4"},
                'Missing or invalid "coordinates"',
            ),
            "pair not a list": (
                {"coordinates": [[1, 2], "3,4"]},
                "Each coordinate must be a list of two numbers",
            ),
            "wrong arity": (
                {"coordinates": [[1, 2], [3, 4, 5]]},
                "Each coordinate must be a list of two numbers",
            ),
            "non-numeric": (
                {"coordinates": [[1, 2], ["east", 4]]},
                "Coordinates must be numeric values.",
            ),
            "null value": (
                {"coordinates": [[1, 2], [None, 4]]},
                "Coordinates must be numeric values.",
            ),
        }
        with patch("apps.trips.services.requests.get") as mock_get:
            for label, (payload, message) in cases.items():
                with self.subTest(label):
                    response = self.client.post(ROUTE_URL, payload, format="json")
                    self.assertEqual(response.status_code, 400)
                    self.assertIn(message, response.data["error"])
            mock_get.assert_not_called()

    @patch("apps.trips.services.requests.get")
    def test_returns_route_geometry(self, mock_get):
        mock_get.return_value = self.osrm_response(
            {"code": "Ok", "routes": [{"geometry": self.GEOMETRY}]}
        )

        response = self.client.post(
            ROUTE_URL, {"coordinates": [list(CHICAGO), list(LONDON)]}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, self.GEOMETRY)
        url = mock_get.call_args.args[0]
        self.assertIn("/-87.6298,41.8781;-0.1278,51.5074?", url)

    @patch("apps.trips.services.requests.get")
    def test_single_coordinate_is_a_routing_error(self, mock_get):
        response = self.client.post(
            ROUTE_URL, {"coordinates": [list(CHICAGO)]}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data["error"], "At least two coordinates are required."
        )
        mock_get.assert_not_called()

    @patch("apps.trips.services.requests.get")
    def test_upstream_failure_surfaces_as_400(self, mock_get):
        mock_get.return_value = self.osrm_response(
            {"code": "NoRoute", "message": "Impossible route"}
        )

        response = self.client.post(
            ROUTE_URL, {"coordinates": [list(CHICAGO), list(LONDON)]}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data["error"], "OSRM returned error: Impossible route"
        )

    def test_requires_authentication(self):
        self.client.force_authenticate(user=None)
        response = self.client.post(
            ROUTE_URL, {"coordinates": [list(CHICAGO), list(LONDON)]}, format="json"
        )
        self.assertEqual(response.status_code, 401)

    def test_get_is_not_allowed(self):
        self.assertEqual(self.client.get(ROUTE_URL).status_code, 405)


class TripLegListRetrieveTests(TripViewTestCase):
    def test_list_aggregates_legs_across_own_trips(self):
        first = self.create_trip_with_stops(CHICAGO, LONDON, PARIS)
        second = self.create_trip_with_stops(PARIS, CHICAGO)
        theirs = self.trips.create("owner-b", {"name": "Theirs", "date": "2026-08-01"})
        self.trips.replace_stops(
            theirs.id,
            "owner-b",
            [{"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0}],
        )

        response = self.client.get(LEGS_URL)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 3)
        self.assertEqual(
            sorted(leg["trip"] for leg in response.data),
            sorted([first["id"], first["id"], second["id"]]),
        )

    def test_list_is_empty_without_trips(self):
        response = self.client.get(LEGS_URL)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, [])

    def test_retrieve_returns_leg(self):
        created = self.create_trip_with_stops(CHICAGO, LONDON)
        leg_id = created["legs"][0]["id"]

        response = self.client.get(f"{LEGS_URL}{leg_id}/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.data,
            {
                "id": leg_id,
                "trip": created["id"],
                "departure_stop": created["stops"][0]["id"],
                "arrival_stop": created["stops"][1]["id"],
                "departure_time": None,
                "arrival_time": None,
                "transport_type": "CAR",
                "booking_reference": "",
                "ticket_data": {},
            },
        )

    def test_retrieve_unknown_leg_returns_404(self):
        self.create_trip_with_stops(CHICAGO, LONDON)
        response = self.client.get(f"{LEGS_URL}does-not-exist/")
        self.assertEqual(response.status_code, 404)

    def test_retrieve_another_owners_leg_returns_404(self):
        theirs = self.trips.create("owner-b", {"name": "Theirs", "date": "2026-08-01"})
        self.trips.replace_stops(
            theirs.id,
            "owner-b",
            [{"lat": 1.0, "lng": 2.0}, {"lat": 3.0, "lng": 4.0}],
        )
        leg_id = self.trips.list_legs(theirs.id, "owner-b")[0].id

        response = self.client.get(f"{LEGS_URL}{leg_id}/")
        self.assertEqual(response.status_code, 404)

    def test_unsupported_methods_return_405(self):
        created = self.create_trip_with_stops(CHICAGO, LONDON)
        leg_url = f"{LEGS_URL}{created['legs'][0]['id']}/"

        self.assertEqual(self.client.post(LEGS_URL, {}, format="json").status_code, 405)
        self.assertEqual(self.client.put(leg_url, {}, format="json").status_code, 405)
        self.assertEqual(self.client.delete(leg_url).status_code, 405)
        self.assertEqual(len(self.trips.list_legs(created["id"], "owner-a")), 1)

    def test_requires_authentication(self):
        self.client.force_authenticate(user=None)
        self.assertEqual(self.client.get(LEGS_URL).status_code, 401)


class TripLegPartialUpdateTests(TripViewTestCase):
    def setUp(self):
        super().setUp()
        self.trip = self.create_trip_with_stops(CHICAGO, LONDON)
        self.leg_id = self.trip["legs"][0]["id"]
        self.leg_url = f"{LEGS_URL}{self.leg_id}/"

    def test_patch_updates_and_persists_fields(self):
        response = self.client.patch(
            self.leg_url,
            {
                "transport_type": "TRAIN",
                "booking_reference": "AMT-42",
                "arrival_time": "2026-08-01T18:30:00Z",
                "ticket_data": {"seat": "12A"},
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["id"], self.leg_id)
        self.assertEqual(response.data["transport_type"], "TRAIN")
        self.assertEqual(response.data["ticket_data"], {"seat": "12A"})

        leg = self.trips.list_legs(self.trip["id"], "owner-a")[0]
        self.assertEqual(leg.booking_reference, "AMT-42")
        self.assertEqual(
            datetime.fromisoformat(leg.arrival_time),
            datetime(2026, 8, 1, 18, 30, tzinfo=UTC),
        )
        # Untouched fields keep their generated values.
        self.assertEqual(leg.departure_stop_id, self.trip["stops"][0]["id"])
        self.assertIsNone(leg.departure_time)

    def test_patch_can_clear_a_time(self):
        self.client.patch(
            self.leg_url, {"departure_time": "2026-08-01T09:00:00Z"}, format="json"
        )
        response = self.client.patch(
            self.leg_url, {"departure_time": None}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.data["departure_time"])
        self.assertIsNone(self.raw_leg(self.trip["id"], self.leg_id)["departure_time"])

    def test_patch_validation_errors_return_400(self):
        cases = {
            "transport_type": {"transport_type": "BOAT"},
            "booking_reference": {"booking_reference": "x" * 101},
            "departure_time": {"departure_time": "tomorrow-ish"},
            "ticket_data": {"ticket_data": ["not", "a", "dict"]},
        }
        for field, payload in cases.items():
            with self.subTest(field):
                response = self.client.patch(self.leg_url, payload, format="json")
                self.assertEqual(response.status_code, 400)
                self.assertIn(field, response.data)
        self.assertEqual(
            self.raw_leg(self.trip["id"], self.leg_id)["transport_type"], "CAR"
        )

    def test_patch_unknown_leg_returns_404(self):
        response = self.client.patch(
            f"{LEGS_URL}does-not-exist/", {"booking_reference": "X"}, format="json"
        )
        self.assertEqual(response.status_code, 404)

    def test_read_only_stop_links_are_ignored(self):
        response = self.client.patch(
            self.leg_url,
            {"departure_stop": "forged", "booking_reference": "X"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["departure_stop"], self.trip["stops"][0]["id"])


class SmartLookupTests(TripViewTestCase):
    def setUp(self):
        super().setUp()
        self.trip = self.create_trip_with_stops(CHICAGO, LONDON)
        self.leg_id = self.trip["legs"][0]["id"]
        self.url = f"{LEGS_URL}{self.leg_id}/smart_lookup/"

    def set_leg(self, **fields):
        self.trips.update_leg(self.trip["id"], self.leg_id, "owner-a", fields)

    def test_flight_lookup_uses_booking_reference_and_merges_ticket_data(self):
        self.set_leg(
            transport_type="FLIGHT",
            booking_reference="ba123",
            ticket_data={"seat": "12A"},
        )

        response = self.client.post(self.url, {}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["departure_time"], "2026-07-04T10:00:00Z")
        self.assertEqual(response.data["arrival_time"], "2026-07-04T13:00:00Z")
        ticket = response.data["ticket_data"]
        self.assertEqual(ticket["seat"], "12A")
        self.assertEqual(ticket["airline"], "British Airways")
        self.assertEqual(ticket["departure"]["iata"], "LHR")

        leg = self.trips.list_legs(self.trip["id"], "owner-a")[0]
        self.assertEqual(leg.departure_time, "2026-07-04T10:00:00Z")
        self.assertEqual(leg.ticket_data["arrival"]["iata"], "JFK")

    def test_identifier_in_body_overrides_booking_reference(self):
        self.set_leg(transport_type="FLIGHT", booking_reference="ZZ999")
        response = self.client.post(self.url, {"identifier": "BA123"}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["ticket_data"]["status"], "scheduled")

    def test_train_lookup(self):
        self.set_leg(transport_type="TRAIN")
        response = self.client.post(self.url, {"identifier": "amt-171"}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["departure_time"], "2026-07-04T08:00:00Z")
        self.assertEqual(response.data["ticket_data"]["arrival"]["station"], "WAS")

    def test_missing_identifier_returns_400(self):
        self.set_leg(transport_type="FLIGHT")
        response = self.client.post(self.url, {}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data, {"error": "Missing identifier"})

    def test_unknown_flight_returns_404_and_leaves_leg_alone(self):
        self.set_leg(transport_type="FLIGHT")
        response = self.client.post(self.url, {"identifier": "XX000"}, format="json")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(
            response.data, {"message": "No data found for this identifier"}
        )
        self.assertEqual(self.raw_leg(self.trip["id"], self.leg_id)["ticket_data"], {})

    def test_road_legs_have_no_lookup(self):
        # Only flights and trains have a lookup source; CAR/BUS never match.
        for transport_type in ("CAR", "BUS"):
            with self.subTest(transport_type):
                self.set_leg(transport_type=transport_type)
                response = self.client.post(
                    self.url, {"identifier": "BA123"}, format="json"
                )
                self.assertEqual(response.status_code, 404)

    @patch("apps.trips.views.TransportLookupService.lookup_flight")
    def test_lookup_without_times_keeps_existing_times(self, mock_lookup):
        mock_lookup.return_value = {"status": "delayed"}
        self.set_leg(
            transport_type="FLIGHT",
            departure_time="2026-08-01T09:00:00+00:00",
            arrival_time="2026-08-01T11:00:00+00:00",
        )

        response = self.client.post(self.url, {"identifier": "BA123"}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["ticket_data"], {"status": "delayed"})
        self.assertEqual(response.data["departure_time"], "2026-08-01T09:00:00+00:00")
        self.assertEqual(response.data["arrival_time"], "2026-08-01T11:00:00+00:00")
        mock_lookup.assert_called_once_with("BA123")

    def test_unknown_leg_returns_404(self):
        response = self.client.post(
            f"{LEGS_URL}does-not-exist/smart_lookup/", {"identifier": "BA123"}
        )
        self.assertEqual(response.status_code, 404)
