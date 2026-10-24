from django.test import SimpleTestCase

from apps.common.geo import haversine_km, parse_lat_lon


class HaversineTests(SimpleTestCase):
    def test_zero_distance(self):
        self.assertAlmostEqual(
            haversine_km(41.8781, -87.6298, 41.8781, -87.6298), 0.0, places=6
        )

    def test_known_distance_chicago_to_midway(self):
        # Downtown Chicago -> Midway International is roughly 14-16 km.
        km = haversine_km(41.8781, -87.6298, 41.7868, -87.7524)
        self.assertGreater(km, 10)
        self.assertLess(km, 20)

    def test_known_distance_chicago_to_jfk(self):
        # Downtown Chicago -> JFK is roughly 1150 km.
        km = haversine_km(41.8781, -87.6298, 40.6413, -73.7781)
        self.assertGreater(km, 1100)
        self.assertLess(km, 1200)

    def test_symmetric(self):
        a = haversine_km(41.8781, -87.6298, 40.6413, -73.7781)
        b = haversine_km(40.6413, -73.7781, 41.8781, -87.6298)
        self.assertAlmostEqual(a, b, places=9)


class ParseLatLonTests(SimpleTestCase):
    def test_parses_query_strings(self):
        self.assertEqual(parse_lat_lon("41.8781", "-87.6298"), (41.8781, -87.6298))

    def test_boundaries_are_valid(self):
        for lat, lon in (("90", "180"), ("-90", "-180"), ("0", "0")):
            with self.subTest(lat=lat, lon=lon):
                self.assertEqual(parse_lat_lon(lat, lon), (float(lat), float(lon)))

    def test_missing_or_non_numeric_rejected(self):
        for lat, lon in ((None, "0"), ("0", None), ("north", "0"), ("", "")):
            with (
                self.subTest(lat=lat, lon=lon),
                self.assertRaisesMessage(ValueError, "must be numbers"),
            ):
                parse_lat_lon(lat, lon)

    def test_non_finite_rejected(self):
        # float() accepts all of these; haversine_km cannot handle them.
        for value in ("inf", "-inf", "nan", "1e309"):
            for lat, lon in ((value, "0"), ("0", value)):
                with (
                    self.subTest(lat=lat, lon=lon),
                    self.assertRaisesMessage(ValueError, "between -90 and 90"),
                ):
                    parse_lat_lon(lat, lon)

    def test_out_of_range_rejected(self):
        out_of_range = (("90.0001", "0"), ("-91", "0"), ("0", "180.5"), ("0", "-181"))
        for lat, lon in out_of_range:
            with (
                self.subTest(lat=lat, lon=lon),
                self.assertRaisesMessage(ValueError, "between -90 and 90"),
            ):
                parse_lat_lon(lat, lon)
