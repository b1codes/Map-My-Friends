from django.contrib.auth.models import User
from django.test import SimpleTestCase
from rest_framework.test import APITestCase

from apps.stations import reference


class StationReferenceTests(SimpleTestCase):
    def test_dataset_loads(self):
        self.assertGreater(len(reference.all_stations()), 100)

    def test_ids_are_unique_integers(self):
        ids = [s.id for s in reference.all_stations()]
        self.assertTrue(all(isinstance(i, int) for i in ids))
        self.assertEqual(len(ids), len(set(ids)))

    def test_get_by_id_round_trips(self):
        first = reference.all_stations()[0]
        self.assertEqual(reference.get_by_id(first.id), first)

    def test_get_by_id_missing_returns_none(self):
        self.assertIsNone(reference.get_by_id(-1))

    def test_get_nearby_respects_count(self):
        self.assertEqual(len(reference.get_nearby(41.8781, -87.6298, count=3)), 3)

    def test_get_nearby_sorted_ascending(self):
        distances = [
            s.distance_km for s in reference.get_nearby(41.8781, -87.6298, count=5)
        ]
        self.assertTrue(all(d is not None for d in distances))
        self.assertEqual(distances, sorted(distances))

    def test_get_nearby_radius_filter(self):
        near = reference.get_nearby(41.8781, -87.6298, radius_km=25, count=10)
        self.assertTrue(all(s.distance_km <= 25 for s in near))

    def test_station_type_filter(self):
        filtered = reference.get_nearby(
            41.8781, -87.6298, count=10, station_type="major_station"
        )
        self.assertTrue(all(s.station_type == "major_station" for s in filtered))

    def test_unknown_station_type_returns_empty(self):
        self.assertEqual(
            reference.get_nearby(41.8781, -87.6298, station_type="not_a_type"), []
        )


class NearestStationsEndpointTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="tester", password="pw12345!")
        self.client.force_authenticate(user=self.user)

    def test_requires_authentication(self):
        self.client.force_authenticate(user=None)
        response = self.client.get("/api/stations/nearest/?lat=41.8781&lon=-87.6298")
        self.assertEqual(response.status_code, 401)

    def test_returns_geojson_features(self):
        response = self.client.get(
            "/api/stations/nearest/?lat=41.8781&lon=-87.6298&count=3"
        )
        self.assertEqual(response.status_code, 200)
        feature = response.data["features"][0]
        self.assertEqual(feature["type"], "Feature")
        self.assertIn("osm_id", feature["properties"])

    def test_station_type_filter_applied(self):
        response = self.client.get(
            "/api/stations/nearest/?lat=41.8781&lon=-87.6298&station_type=major_station"
        )
        self.assertEqual(response.status_code, 200)
        for feature in response.data["features"]:
            self.assertEqual(feature["properties"]["station_type"], "major_station")

    def test_missing_params_return_400(self):
        response = self.client.get("/api/stations/nearest/")
        self.assertEqual(response.status_code, 400)
