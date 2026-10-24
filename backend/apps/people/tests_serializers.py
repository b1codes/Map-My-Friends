"""Unit tests for PersonSerializer and ContactLogSerializer.

Pure serialization: records are built in memory, so no emulator is needed.
Airports and stations come from the bundled reference exports.
"""

from django.contrib.auth.models import AnonymousUser, User
from django.test import SimpleTestCase
from rest_framework.test import APIRequestFactory

from apps.people.repositories import ContactLogRecord, PersonRecord
from apps.people.serializers import ContactLogSerializer, PersonSerializer

# Ids that exist in airports_export.json / stations_export.json.
KNOWN_AIRPORT = 1  # Anaa Airport (AAA)
KNOWN_STATION = 1  # 1st Street
UNKNOWN_ID = 10**9


def make_request(user=None):
    request = APIRequestFactory().get("/api/people/")
    request.user = user or AnonymousUser()
    return request


def make_person(**overrides):
    return PersonRecord(
        **{
            "id": "p1",
            "owner_key": "owner-a",
            "tag": "FRIEND",
            "first_name": "Ada",
            "lat": 51.5,
            "lng": -0.12,
            "last_contacted_at": "2026-07-01T12:00:00+00:00",
            "last_contact_channel": "CALL",
            **overrides,
        }
    )


class PersonRepresentationTests(SimpleTestCase):
    def test_feature_envelope(self):
        data = PersonSerializer(make_person()).data

        self.assertEqual(data["id"], "p1")
        self.assertEqual(data["type"], "Feature")
        self.assertEqual(
            data["geometry"], {"type": "Point", "coordinates": [-0.12, 51.5]}
        )
        self.assertEqual(data["properties"]["owner"], "owner-a")

    def test_missing_coordinates_give_null_geometry(self):
        data = PersonSerializer(make_person(lat=None, lng=None)).data
        self.assertIsNone(data["geometry"])

    def test_many_wraps_in_a_feature_collection(self):
        data = PersonSerializer(
            [make_person(id="p1"), make_person(id="p2")], many=True
        ).data
        self.assertEqual(data["type"], "FeatureCollection")
        self.assertEqual([f["id"] for f in data["features"]], ["p1", "p2"])

    def test_recency_fields_shown_to_authenticated_callers(self):
        request = make_request(User(username="owner-a"))
        props = PersonSerializer(make_person(), context={"request": request}).data[
            "properties"
        ]
        self.assertEqual(props["last_contacted_at"], "2026-07-01T12:00:00+00:00")
        self.assertEqual(props["last_contact_channel"], "CALL")

    def test_recency_fields_hidden_without_an_authenticated_request(self):
        contexts = {
            "anonymous": {"request": make_request()},
            "no request": {},
        }
        for label, context in contexts.items():
            with self.subTest(label):
                props = PersonSerializer(make_person(), context=context).data[
                    "properties"
                ]
                self.assertNotIn("last_contacted_at", props)
                self.assertNotIn("last_contact_channel", props)

    def test_profile_image_url(self):
        cases = {
            "unset": (None, None, None),
            "relative without request": (
                "profile_images/a.png",
                None,
                "/media/profile_images/a.png",
            ),
            "absolute with request": (
                "profile_images/a.png",
                make_request(),
                "http://testserver/media/profile_images/a.png",
            ),
        }
        for label, (name, request, expected) in cases.items():
            with self.subTest(label):
                data = PersonSerializer(
                    make_person(profile_image=name), context={"request": request}
                ).data
                self.assertEqual(data["properties"]["profile_image"], expected)

    def test_preferred_airport_detail(self):
        cases = {
            "unset": (None, None),
            "known": (KNOWN_AIRPORT, "AAA"),
            # An id no longer in the reference export (e.g. after a
            # re-fetch dropped it) degrades to null rather than erroring.
            "stale": (UNKNOWN_ID, None),
        }
        for label, (airport_id, iata) in cases.items():
            with self.subTest(label):
                detail = PersonSerializer(
                    make_person(preferred_airport=airport_id)
                ).data["properties"]["preferred_airport_detail"]
                if iata is None:
                    self.assertIsNone(detail)
                else:
                    self.assertEqual(detail["type"], "Feature")
                    self.assertEqual(detail["properties"]["iata_code"], iata)

    def test_preferred_station_detail(self):
        cases = {
            "unset": (None, None),
            "known": (KNOWN_STATION, "1st Street"),
            "stale": (UNKNOWN_ID, None),
        }
        for label, (station_id, name) in cases.items():
            with self.subTest(label):
                detail = PersonSerializer(
                    make_person(preferred_station=station_id)
                ).data["properties"]["preferred_station_detail"]
                if name is None:
                    self.assertIsNone(detail)
                else:
                    self.assertEqual(detail["properties"]["name"], name)


class PersonValidationTests(SimpleTestCase):
    def validate(self, **data):
        serializer = PersonSerializer(data={"tag": "FRIEND", **data})
        return serializer.is_valid(), serializer

    def test_minimal_payload_is_valid(self):
        is_valid, serializer = self.validate()
        self.assertTrue(is_valid, serializer.errors)
        self.assertEqual(serializer.validated_data, {"tag": "FRIEND"})

    def test_reference_ids_are_checked_against_the_exports(self):
        cases = {
            "preferred_airport": "Unknown airport id.",
            "preferred_station": "Unknown station id.",
        }
        for field, message in cases.items():
            with self.subTest(field):
                is_valid, serializer = self.validate(**{field: UNKNOWN_ID})
                self.assertFalse(is_valid)
                self.assertEqual(serializer.errors[field], [message])

    def test_known_or_null_reference_ids_are_valid(self):
        for airport, station in ((KNOWN_AIRPORT, KNOWN_STATION), (None, None)):
            with self.subTest(airport=airport, station=station):
                is_valid, serializer = self.validate(
                    preferred_airport=airport, preferred_station=station
                )
                self.assertTrue(is_valid, serializer.errors)
                data = serializer.validated_data
                self.assertEqual(data["preferred_airport"], airport)
                self.assertEqual(data["preferred_station"], station)

    def test_birthday_input_formats(self):
        for raw in ("1990-01-02", "1990-01-02T00:00:00.000", "1990-01-02T00:00:00"):
            with self.subTest(raw):
                is_valid, serializer = self.validate(birthday=raw)
                self.assertTrue(is_valid, serializer.errors)
                self.assertEqual(
                    serializer.validated_data["birthday"].isoformat(), "1990-01-02"
                )

    def test_read_only_fields_are_dropped(self):
        is_valid, serializer = self.validate(
            id="x", owner="owner-b", lat=1.0, lng=2.0, timezone="UTC"
        )
        self.assertTrue(is_valid)
        self.assertEqual(serializer.validated_data, {"tag": "FRIEND"})


class ContactLogSerializerTests(SimpleTestCase):
    def test_person_maps_to_person_id(self):
        data = ContactLogSerializer(
            ContactLogRecord(
                id="l1",
                person_id="p1",
                channel="CALL",
                contacted_at="2026-07-01T12:00:00+00:00",
                note="Hi",
                created_at="2026-07-01T12:00:01+00:00",
            )
        ).data

        self.assertEqual(
            dict(data),
            {
                "id": "l1",
                "person": "p1",
                "channel": "CALL",
                "contacted_at": "2026-07-01T12:00:00+00:00",
                "note": "Hi",
                "created_at": "2026-07-01T12:00:01+00:00",
            },
        )

    def test_validated_data_uses_person_id(self):
        serializer = ContactLogSerializer(
            data={
                "person": "p1",
                "channel": "MESSAGE",
                "contacted_at": "2026-07-01T12:00:00Z",
                "note": "",
            }
        )
        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertEqual(serializer.validated_data["person_id"], "p1")
        self.assertEqual(serializer.validated_data["note"], "")
