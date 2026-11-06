import json
import tempfile
from pathlib import Path
from unittest import mock

from django.contrib.auth.models import User
from rest_framework.test import APITestCase

from apps.common.geo import haversine_km
from apps.stations import reference
from apps.stations.views import VALID_STATION_TYPES

URL = "/api/stations/nearest/"
CHICAGO = {"lat": 41.8781, "lon": -87.6298}

FIXTURE_STATIONS = [
    {
        "id": 1,
        "name": "Chicago Union Station",
        "osm_id": 1001,
        "station_type": "major_station",
        "uic_ref": "CHI",
        "city": "Chicago",
        "country": "USA",
        "lat": 41.8786,
        "lon": -87.6403,
    },
    {
        "id": 2,
        "name": "Harold Washington Library",
        "osm_id": 1002,
        "station_type": "subway_station",
        "uic_ref": "",
        "city": "Chicago",
        "country": "USA",
        "lat": 41.8768,
        "lon": -87.6282,
    },
    {
        "id": 3,
        "name": "Ogilvie Transportation Center",
        "osm_id": 1003,
        "station_type": "commuter_rail_station",
        "uic_ref": "",
        "city": "Chicago",
        "country": "USA",
        "lat": 41.8831,
        "lon": -87.6405,
    },
    {
        # Older exports omitted station_type and stored nulls for blanks.
        "id": 4,
        "name": "Joliet",
        "osm_id": 1004,
        "uic_ref": None,
        "city": None,
        "country": "USA",
        "lat": 41.5250,
        "lon": -88.0817,
    },
]


class _FixtureDatasetMixin:
    """Points the in-memory index at a small, known dataset for exact assertions."""

    dataset = FIXTURE_STATIONS

    def setUp(self):
        super().setUp()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = Path(tmp.name) / "stations_export.json"
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

    def _ids(self, params):
        response = self.client.get(URL, params)
        self.assertEqual(response.status_code, 200)
        return [f["id"] for f in response.data["features"]]


class NearestStationsResponseShapeTests(
    _FixtureDatasetMixin, _AuthenticatedMixin, APITestCase
):
    def test_wrapped_in_feature_collection(self):
        response = self.client.get(URL, CHICAGO)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["type"], "FeatureCollection")
        self.assertEqual(len(response.data["features"]), 3)

    def test_feature_carries_every_field_the_client_reads(self):
        response = self.client.get(
            URL, {**CHICAGO, "count": 1, "station_type": "major_station"}
        )
        feature = response.data["features"][0]
        self.assertEqual(feature["id"], 1)
        self.assertEqual(feature["type"], "Feature")
        self.assertEqual(
            feature["geometry"], {"type": "Point", "coordinates": [-87.6403, 41.8786]}
        )
        self.assertEqual(
            feature["properties"],
            {
                "name": "Chicago Union Station",
                "osm_id": 1001,
                "station_type": "major_station",
                "uic_ref": "CHI",
                "city": "Chicago",
                "country": "USA",
                "distance_km": round(
                    haversine_km(41.8781, -87.6298, 41.8786, -87.6403), 1
                ),
            },
        )

    def test_ordered_nearest_first(self):
        self.assertEqual(self._ids({**CHICAGO, "count": 10}), [2, 1, 3, 4])

    def test_each_station_type_filters_results(self):
        expected = {
            "major_station": [1],
            "subway_station": [2],
            "commuter_rail_station": [3],
            # Joliet has no station_type in the source and defaults to regional.
            "regional_station": [4],
        }
        self.assertEqual(set(expected), VALID_STATION_TYPES)
        for station_type, ids in expected.items():
            with self.subTest(station_type=station_type):
                self.assertEqual(
                    self._ids({**CHICAGO, "station_type": station_type}), ids
                )

    def test_unknown_station_type_is_ignored_not_rejected(self):
        # Unlike the reference function (which returns []), the endpoint
        # treats an unrecognised filter as no filter.
        for station_type in ("airport", "MAJOR_STATION", ""):
            with self.subTest(station_type=station_type):
                self.assertEqual(
                    self._ids({**CHICAGO, "station_type": station_type}), [2, 1, 3]
                )

    def test_count_applies_after_filter(self):
        self.assertEqual(
            self._ids({**CHICAGO, "count": 1, "station_type": "commuter_rail_station"}),
            [3],
        )

    def test_null_source_fields_serialise_as_blank_strings(self):
        response = self.client.get(URL, {**CHICAGO, "station_type": "regional_station"})
        properties = response.data["features"][0]["properties"]
        self.assertEqual(properties["uic_ref"], "")
        self.assertEqual(properties["city"], "")


class NearestStationsNoMatchTests(
    _FixtureDatasetMixin, _AuthenticatedMixin, APITestCase
):
    dataset = [FIXTURE_STATIONS[3]]

    def test_filter_with_no_matches_returns_empty_feature_collection(self):
        response = self.client.get(URL, {**CHICAGO, "station_type": "subway_station"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, {"type": "FeatureCollection", "features": []})


class NearestStationsEmptyDatasetTests(
    _FixtureDatasetMixin, _AuthenticatedMixin, APITestCase
):
    dataset = []

    def test_empty_dataset_returns_empty_feature_collection(self):
        response = self.client.get(URL, CHICAGO)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, {"type": "FeatureCollection", "features": []})


class NearestStationsParameterTests(_AuthenticatedMixin, APITestCase):
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

    def test_non_numeric_coordinates_return_400(self):
        self._assert_bad_coordinates({"lat": "north", "lon": "west"})

    def test_lng_is_not_an_alias_for_lon(self):
        self._assert_bad_coordinates({"lat": 41.8781, "lng": -87.6298})

    def test_bad_coordinates_rejected_even_with_valid_filter(self):
        self._assert_bad_coordinates({"lat": "x", "station_type": "major_station"})

    def test_default_count_is_three(self):
        self.assertEqual(len(self._ids(CHICAGO)), 3)

    def test_count_is_clamped_to_ten(self):
        self.assertEqual(len(self._ids({**CHICAGO, "count": 99})), 10)

    def test_count_below_one_is_clamped_to_one(self):
        for count in (0, -5):
            with self.subTest(count=count):
                self.assertEqual(len(self._ids({**CHICAGO, "count": count})), 1)

    def test_invalid_count_falls_back_to_default(self):
        for count in ("many", "2.5", ""):
            with self.subTest(count=count):
                self.assertEqual(len(self._ids({**CHICAGO, "count": count})), 3)

    def test_post_not_allowed(self):
        response = self.client.post(URL, CHICAGO)
        self.assertEqual(response.status_code, 405)
