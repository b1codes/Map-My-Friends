from django.test import SimpleTestCase
from rest_framework import serializers

from apps.trips.repositories import TripStopRecord
from apps.trips.serializers import PointField, TripStopSerializer


class PointFieldTests(SimpleTestCase):
    """The GeoJSON contract is [longitude, latitude]; Firestore stores flat
    lat/lng, so the field has to translate in both directions."""

    def setUp(self):
        self.field = PointField()

    def test_representation_is_lng_lat_point(self):
        record = TripStopRecord(id="s1", trip_id="t1", lat=41.8781, lng=-87.6298)
        self.assertEqual(
            self.field.to_representation(self.field.get_attribute(record)),
            {"type": "Point", "coordinates": [-87.6298, 41.8781]},
        )

    def test_representation_without_coordinates_is_none(self):
        for lat, lng in ((None, None), (1.0, None), (None, 1.0)):
            with self.subTest(lat=lat, lng=lng):
                record = TripStopRecord(id="s1", trip_id="t1", lat=lat, lng=lng)
                self.assertIsNone(self.field.to_representation(record))

    def test_internal_value_swaps_to_lat_lng(self):
        self.assertEqual(
            self.field.to_internal_value({"type": "Point", "coordinates": ["2.5", 48]}),
            {"lat": 48.0, "lng": 2.5},
        )

    def test_accepts_range_boundaries(self):
        self.assertEqual(
            self.field.to_internal_value({"coordinates": [-180, 90]}),
            {"lat": 90.0, "lng": -180.0},
        )

    def test_invalid_values_are_rejected(self):
        cases = {
            "not an object": ([-87.6, 41.8], "Expected a GeoJSON Point"),
            "missing coordinates": ({"type": "Point"}, "two-element"),
            "three coordinates": ({"coordinates": [1, 2, 3]}, "two-element"),
            "string coordinates": ({"coordinates": "1,2"}, "two-element"),
            "non-numeric": ({"coordinates": ["east", 2]}, "must be numbers"),
            "null member": ({"coordinates": [None, 2]}, "must be numbers"),
            "latitude out of range": ({"coordinates": [0, 90.1]}, "out of range"),
            "longitude out of range": ({"coordinates": [180.1, 0]}, "out of range"),
        }
        for label, (value, message) in cases.items():
            with self.subTest(label):
                with self.assertRaises(serializers.ValidationError) as ctx:
                    self.field.to_internal_value(value)
                self.assertIn(message, str(ctx.exception.detail[0]))


class TripStopSerializerTests(SimpleTestCase):
    def test_partial_still_requires_location(self):
        serializer = TripStopSerializer(data={"sequence_order": 0}, partial=True)
        self.assertFalse(serializer.is_valid())
        self.assertEqual(serializer.errors["location"], ["This field is required."])

    def test_location_is_flattened_into_validated_data(self):
        serializer = TripStopSerializer(
            data={
                "sequence_order": 3,
                "location": {"type": "Point", "coordinates": [-0.1278, 51.5074]},
                "people": ["p1"],
                "airport": None,
            }
        )
        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertEqual(
            dict(serializer.validated_data),
            {
                "sequence_order": 3,
                "lat": 51.5074,
                "lng": -0.1278,
                "person_ids": ["p1"],
                "airport_id": None,
            },
        )

    def test_stop_without_coordinates_serializes_location_as_null(self):
        record = TripStopRecord(id="s1", trip_id="t1")
        self.assertIsNone(TripStopSerializer(record).data["location"])
