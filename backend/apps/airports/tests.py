from django.contrib.auth.models import User
from django.test import SimpleTestCase
from rest_framework.test import APITestCase

from apps.airports import reference


class AirportReferenceTests(SimpleTestCase):
    """Exercises the in-memory index against the committed dataset."""

    def test_dataset_loads(self):
        airports = reference.all_airports()
        self.assertGreater(len(airports), 4000)

    def test_ids_are_unique_integers(self):
        ids = [a.id for a in reference.all_airports()]
        self.assertTrue(all(isinstance(i, int) for i in ids))
        self.assertEqual(len(ids), len(set(ids)))

    def test_get_by_id_round_trips(self):
        first = reference.all_airports()[0]
        self.assertEqual(reference.get_by_id(first.id), first)

    def test_get_by_id_missing_returns_none(self):
        self.assertIsNone(reference.get_by_id(-1))

    def test_get_nearby_sorting(self):
        # Downtown Chicago: Midway is closer than O'Hare.
        nearby = reference.get_nearby(41.8781, -87.6298, count=10)
        codes = [a.iata_code for a in nearby]
        self.assertIn("MDW", codes)
        self.assertIn("ORD", codes)
        self.assertLess(codes.index("MDW"), codes.index("ORD"))

    def test_get_nearby_respects_count(self):
        self.assertEqual(len(reference.get_nearby(41.8781, -87.6298, count=3)), 3)

    def test_get_nearby_radius_filter(self):
        within_20 = reference.get_nearby(41.8781, -87.6298, radius_km=20, count=10)
        codes = [a.iata_code for a in within_20]
        self.assertIn("MDW", codes)
        self.assertNotIn("JFK", codes)

    def test_distance_km_populated_and_ascending(self):
        nearby = reference.get_nearby(41.8781, -87.6298, count=5)
        distances = [a.distance_km for a in nearby]
        self.assertTrue(all(d is not None for d in distances))
        self.assertEqual(distances, sorted(distances))

    def test_distance_km_plausible(self):
        nearest = reference.get_nearby(41.8781, -87.6298, count=1)[0]
        self.assertGreater(nearest.distance_km, 0)
        self.assertLess(nearest.distance_km, 40)


class NearestAirportsEndpointTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="tester", password="pw12345!")
        self.client.force_authenticate(user=self.user)

    def test_requires_authentication(self):
        self.client.force_authenticate(user=None)
        response = self.client.get("/api/airports/nearest/?lat=41.8781&lon=-87.6298")
        self.assertEqual(response.status_code, 401)

    def test_returns_geojson_features(self):
        response = self.client.get(
            "/api/airports/nearest/?lat=41.8781&lon=-87.6298&count=3"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["features"]), 3)
        feature = response.data["features"][0]
        self.assertEqual(feature["type"], "Feature")
        self.assertEqual(feature["geometry"]["type"], "Point")
        self.assertIn("iata_code", feature["properties"])
        self.assertIn("distance_km", feature["properties"])

    def test_missing_params_return_400(self):
        response = self.client.get("/api/airports/nearest/")
        self.assertEqual(response.status_code, 400)

    def test_count_is_clamped_to_ten(self):
        response = self.client.get(
            "/api/airports/nearest/?lat=41.8781&lon=-87.6298&count=99"
        )
        self.assertEqual(len(response.data["features"]), 10)
