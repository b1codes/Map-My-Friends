import json
import tempfile
from pathlib import Path
from unittest import mock

from django.contrib.auth.models import User
from rest_framework.test import APITestCase

from apps.airports import reference
from apps.common.geo import haversine_km

URL = "/api/airports/nearest/"
CHICAGO = {"lat": 41.8781, "lon": -87.6298}

FIXTURE_AIRPORTS = [
    {
        "id": 10,
        "name": "Chicago Midway International Airport",
        "iata": "MDW",
        "icao": "KMDW",
        "type": "large_airport",
        "city": "Chicago",
        "country": "US",
        "continent": "NA",
        "lat": 41.7868,
        "lon": -87.7522,
    },
    {
        "id": 11,
        "name": "Chicago O'Hare International Airport",
        "iata": "ORD",
        "icao": "KORD",
        "type": "large_airport",
        "city": "Chicago",
        "country": "US",
        "continent": "NA",
        "lat": 41.9786,
        "lon": -87.9048,
    },
    {
        # Nulls appear in the OurAirports export for some records.
        "id": 12,
        "name": "John F Kennedy International Airport",
        "iata": "JFK",
        "icao": None,
        "type": "large_airport",
        "city": None,
        "country": "US",
        "continent": None,
        "lat": 40.6398,
        "lon": -73.7789,
    },
]


class _FixtureDatasetMixin:
    """Points the in-memory index at a small, known dataset for exact assertions."""

    dataset = FIXTURE_AIRPORTS

    def setUp(self):
        super().setUp()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = Path(tmp.name) / "airports_export.json"
        path.write_text(json.dumps(self.dataset), encoding="utf-8")

        # Registered first so it runs last: the cache is cleared only once the
        # real DATA_FILE is back, so later tests reload the committed dataset.
        self.addCleanup(reference._load.cache_clear)
        patcher = mock.patch.object(reference, "DATA_FILE", path)
        patcher.start()
        self.addCleanup(patcher.stop)
        reference._load.cache_clear()


class _AuthenticatedMixin:
    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(username="tester", password="pw12345!")
        self.client.force_authenticate(user=self.user)


class NearestAirportsResponseShapeTests(
    _FixtureDatasetMixin, _AuthenticatedMixin, APITestCase
):
    def test_wrapped_in_feature_collection(self):
        response = self.client.get(URL, CHICAGO)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["type"], "FeatureCollection")
        self.assertEqual(len(response.data["features"]), 3)

    def test_feature_carries_every_field_the_client_reads(self):
        response = self.client.get(URL, {**CHICAGO, "count": 1})
        feature = response.data["features"][0]
        self.assertEqual(feature["id"], 10)
        self.assertEqual(feature["type"], "Feature")
        self.assertEqual(
            feature["geometry"], {"type": "Point", "coordinates": [-87.7522, 41.7868]}
        )
        self.assertEqual(
            feature["properties"],
            {
                "name": "Chicago Midway International Airport",
                "iata_code": "MDW",
                "icao_code": "KMDW",
                "airport_type": "large_airport",
                "city": "Chicago",
                "country": "US",
                "continent": "NA",
                "distance_km": round(
                    haversine_km(41.8781, -87.6298, 41.7868, -87.7522), 1
                ),
            },
        )

    def test_null_source_fields_serialise_as_blank_strings(self):
        # The loader normalises nulls, so text properties are always strings.
        response = self.client.get(URL, {"lat": 40.6398, "lon": -73.7789, "count": 1})
        properties = response.data["features"][0]["properties"]
        self.assertEqual(properties["iata_code"], "JFK")
        self.assertEqual(properties["icao_code"], "")
        self.assertEqual(properties["city"], "")
        self.assertEqual(properties["continent"], "")
        self.assertEqual(properties["distance_km"], 0.0)

    def test_ordered_nearest_first(self):
        response = self.client.get(URL, CHICAGO)
        codes = [f["properties"]["iata_code"] for f in response.data["features"]]
        self.assertEqual(codes, ["MDW", "ORD", "JFK"])
        distances = [f["properties"]["distance_km"] for f in response.data["features"]]
        self.assertEqual(distances, sorted(distances))

    def test_count_larger_than_dataset_returns_everything(self):
        response = self.client.get(URL, {**CHICAGO, "count": 10})
        self.assertEqual(len(response.data["features"]), 3)

    def test_results_do_not_mutate_cached_index(self):
        self.client.get(URL, CHICAGO)
        self.assertTrue(all(a.distance_km is None for a in reference.all_airports()))


class NearestAirportsEmptyDatasetTests(
    _FixtureDatasetMixin, _AuthenticatedMixin, APITestCase
):
    dataset = []

    def test_empty_dataset_returns_empty_feature_collection(self):
        # The client indexes data['features'] unconditionally, so "no results"
        # must still be a FeatureCollection, not [] or a 404.
        response = self.client.get(URL, CHICAGO)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, {"type": "FeatureCollection", "features": []})


class NearestAirportsParameterTests(_AuthenticatedMixin, APITestCase):
    """Runs against the committed dataset, which is large enough to clamp."""

    def _assert_bad_coordinates(self, params):
        response = self.client.get(URL, params)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data,
            {"error": "lat and lon query parameters are required and must be numbers."},
        )

    def _assert_invalid_coordinates(self, params):
        response = self.client.get(URL, params)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data,
            {"error": "lat must be between -90 and 90 and lon between -180 and 180."},
        )

    def test_non_finite_coordinates_return_400(self):
        # Previously a 500: float() accepts these but haversine_km cannot.
        for value in ("inf", "-inf", "nan", "1e309"):
            for params in ({"lat": value, "lon": 0}, {"lat": 0, "lon": value}):
                with self.subTest(**params):
                    self._assert_invalid_coordinates(params)

    def test_out_of_range_coordinates_return_400(self):
        # Previously a 200 with meaningless results.
        for params in (
            {"lat": 90.0001, "lon": 0},
            {"lat": -91, "lon": 0},
            {"lat": 0, "lon": 180.5},
            {"lat": 0, "lon": -181},
            {"lat": 999, "lon": 999},
        ):
            with self.subTest(**params):
                self._assert_invalid_coordinates(params)

    def test_boundary_coordinates_are_valid(self):
        for params in ({"lat": 90, "lon": 180}, {"lat": -90, "lon": -180}):
            with self.subTest(**params):
                response = self.client.get(URL, {**params, "count": 1})
                self.assertEqual(response.status_code, 200)
                self.assertEqual(len(response.data["features"]), 1)

    def test_missing_lat_returns_400(self):
        self._assert_bad_coordinates({"lon": -87.6298})

    def test_missing_lon_returns_400(self):
        self._assert_bad_coordinates({"lat": 41.8781})

    def test_non_numeric_lat_returns_400(self):
        self._assert_bad_coordinates({"lat": "north", "lon": -87.6298})

    def test_non_numeric_lon_returns_400(self):
        self._assert_bad_coordinates({"lat": 41.8781, "lon": "west"})

    def test_blank_coordinates_return_400(self):
        self._assert_bad_coordinates({"lat": "", "lon": ""})

    def test_lng_is_not_an_alias_for_lon(self):
        # The parameter is `lon` (what airport_service.dart sends), even though
        # the response and the rest of the API say `lng`.
        self._assert_bad_coordinates({"lat": 41.8781, "lng": -87.6298})

    def test_default_count_is_three(self):
        response = self.client.get(URL, CHICAGO)
        self.assertEqual(len(response.data["features"]), 3)

    def test_count_below_one_is_clamped_to_one(self):
        for count in (0, -5):
            with self.subTest(count=count):
                response = self.client.get(URL, {**CHICAGO, "count": count})
                self.assertEqual(response.status_code, 200)
                self.assertEqual(len(response.data["features"]), 1)

    def test_invalid_count_falls_back_to_default(self):
        for count in ("many", "2.5", ""):
            with self.subTest(count=count):
                response = self.client.get(URL, {**CHICAGO, "count": count})
                self.assertEqual(response.status_code, 200)
                self.assertEqual(len(response.data["features"]), 3)

    def test_integer_coordinates_accepted(self):
        response = self.client.get(URL, {"lat": 42, "lon": -88, "count": 1})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["features"]), 1)

    def test_post_not_allowed(self):
        response = self.client.post(URL, CHICAGO)
        self.assertEqual(response.status_code, 405)
