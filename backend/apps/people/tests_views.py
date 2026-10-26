"""Functional tests for /api/people/ (PersonViewSet).

Ownership isolation is covered in tests.py and tests/test_api_security.py;
these cover each action's behaviour: response bodies, persisted Firestore
state, validation, geocoding and uploads. Geocoding is the only thing mocked
because it is a Nominatim network call.
"""

import shutil
import tempfile
from unittest.mock import patch

from django.contrib.auth.models import User
from django.core.exceptions import ValidationError
from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase

from apps.common import firestore as fs
from apps.common.testing import FirestoreTestMixin, ThrottleIsolationMixin
from apps.people.repositories import ContactLogRepository, PersonRepository
from apps.people.services import GeocodingUnavailable

LONDON = (51.5074, -0.1278, "Europe/London")
PARIS = (48.8566, 2.3522, "Europe/Paris")

PERSON_PAYLOAD = {
    "tag": "FRIEND",
    "first_name": "Ada",
    "last_name": "Lovelace",
    "city": "London",
    "state": "England",
    "country": "UK",
}

# Lat/lng are written by the view after geocoding; repository-seeded records
# supply them directly.
SEEDED_PERSON = {**PERSON_PAYLOAD, "lat": 51.5074, "lng": -0.1278}


def stored(person_id):
    """The raw Firestore document, bypassing the repository's hydration."""
    return fs.collection("people").document(person_id).get()


class PersonTestCase(ThrottleIsolationMixin, FirestoreTestMixin, APITestCase):
    collections_to_purge = ["people"]

    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(username="owner-a", password="pw12345!")
        self.other = User.objects.create_user(username="owner-b", password="pw12345!")
        self.people = PersonRepository()


@patch("apps.people.views.geocode_address", return_value=LONDON)
class PersonListTests(PersonTestCase):
    def test_anonymous_list_is_exactly_the_public_dataset(self, _geocode):
        public = self.people.create(None, SEEDED_PERSON)
        self.people.create("owner-a", SEEDED_PERSON)

        response = self.client.get("/api/people/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["type"], "FeatureCollection")
        self.assertEqual([f["id"] for f in response.data["features"]], [public.id])

    def test_authenticated_list_excludes_the_public_dataset(self, _geocode):
        # Authenticated callers see their own people only, not public ones.
        self.people.create(None, SEEDED_PERSON)
        own = self.people.create("owner-a", SEEDED_PERSON)
        self.client.force_authenticate(user=self.user)

        response = self.client.get("/api/people/")

        self.assertEqual([f["id"] for f in response.data["features"]], [own.id])

    def test_empty_list_is_still_a_feature_collection(self, _geocode):
        self.client.force_authenticate(user=self.user)
        response = self.client.get("/api/people/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, {"type": "FeatureCollection", "features": []})

    def test_features_carry_lng_lat_geometry_and_owner(self, _geocode):
        self.people.create("owner-a", SEEDED_PERSON)
        self.client.force_authenticate(user=self.user)

        feature = self.client.get("/api/people/").data["features"][0]

        self.assertEqual(
            feature["geometry"], {"type": "Point", "coordinates": [-0.1278, 51.5074]}
        )
        self.assertEqual(feature["properties"]["owner"], "owner-a")
        # lat/lng/id are lifted into the envelope, not duplicated in properties.
        for key in ("lat", "lng", "id"):
            self.assertNotIn(key, feature["properties"])


@patch("apps.people.views.geocode_address", return_value=LONDON)
class PersonRetrieveTests(PersonTestCase):
    def test_owner_retrieves_own_person(self, _geocode):
        person = self.people.create("owner-a", SEEDED_PERSON)
        self.client.force_authenticate(user=self.user)

        response = self.client.get(f"/api/people/{person.id}/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["id"], person.id)
        props = response.data["properties"]
        self.assertEqual(props["first_name"], "Ada")
        self.assertEqual(props["owner"], "owner-a")
        # Recency fields are present for an authenticated caller, null until
        # a contact is logged.
        self.assertIsNone(props["last_contacted_at"])
        self.assertIsNone(props["last_contact_channel"])

    def test_anonymous_retrieves_public_person_without_recency(self, _geocode):
        person = self.people.create(None, SEEDED_PERSON)

        response = self.client.get(f"/api/people/{person.id}/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["id"], person.id)
        self.assertNotIn("last_contacted_at", response.data["properties"])
        self.assertNotIn("last_contact_channel", response.data["properties"])

    def test_anonymous_cannot_retrieve_an_owned_person(self, _geocode):
        person = self.people.create("owner-a", SEEDED_PERSON)
        response = self.client.get(f"/api/people/{person.id}/")
        self.assertEqual(response.status_code, 404)

    def test_authenticated_cannot_retrieve_a_public_person(self, _geocode):
        person = self.people.create(None, SEEDED_PERSON)
        self.client.force_authenticate(user=self.user)
        response = self.client.get(f"/api/people/{person.id}/")
        self.assertEqual(response.status_code, 404)

    def test_unknown_id_is_404(self, _geocode):
        self.client.force_authenticate(user=self.user)
        response = self.client.get("/api/people/does-not-exist/")
        self.assertEqual(response.status_code, 404)


@patch("apps.people.views.geocode_address", return_value=LONDON)
class PersonCreateTests(PersonTestCase):
    def setUp(self):
        super().setUp()
        self.client.force_authenticate(user=self.user)

    def test_create_persists_owner_coordinates_and_timestamps(self, _geocode):
        response = self.client.post("/api/people/", PERSON_PAYLOAD, format="json")

        self.assertEqual(response.status_code, 201)
        doc = stored(response.data["id"]).to_dict()
        self.assertEqual(doc["owner_key"], "owner-a")
        self.assertEqual(doc["first_name"], "Ada")
        self.assertEqual((doc["lat"], doc["lng"]), (51.5074, -0.1278))
        self.assertEqual(doc["timezone"], "Europe/London")
        self.assertIn("created_at", doc)
        self.assertIn("updated_at", doc)

    def test_create_geocodes_the_submitted_address(self, geocode):
        self.client.post(
            "/api/people/",
            {**PERSON_PAYLOAD, "street": "12 St James's Square"},
            format="json",
        )
        geocode.assert_called_once_with(
            "London", "England", "UK", "12 St James's Square"
        )

    def test_create_response_applies_pin_defaults(self, _geocode):
        props = self.client.post("/api/people/", PERSON_PAYLOAD, format="json").data[
            "properties"
        ]

        self.assertEqual(props["pin_color"], "#F44336")
        self.assertEqual(props["pin_style"], "teardrop")
        self.assertEqual(props["pin_icon_type"], "none")
        self.assertEqual(props["timezone"], "Europe/London")
        self.assertIsNone(props["profile_image"])

    def test_create_round_trips_optional_fields(self, _geocode):
        payload = {
            **PERSON_PAYLOAD,
            "tag": "FAMILY",
            "phone_number": "+44 20 7946 0000",
            "pin_color": "#00FF00",
            "pin_style": "diamond",
            "pin_icon_type": "emoji",
            "pin_emoji": "🎉",
            "contact_cadence_days": 30,
            "birthday": None,
        }
        response = self.client.post("/api/people/", payload, format="json")

        self.assertEqual(response.status_code, 201)
        props = response.data["properties"]
        for key in (
            "tag",
            "phone_number",
            "pin_color",
            "pin_style",
            "pin_icon_type",
            "pin_emoji",
            "contact_cadence_days",
        ):
            self.assertEqual(props[key], payload[key], key)
        self.assertIsNone(props["birthday"])

    def test_read_only_fields_supplied_by_client_are_ignored(self, _geocode):
        response = self.client.post(
            "/api/people/",
            {
                **PERSON_PAYLOAD,
                "lat": 1.0,
                "lng": 2.0,
                "timezone": "Asia/Tokyo",
                "owner": "owner-b",
                "last_contact_channel": "CALL",
            },
            format="json",
        )

        doc = stored(response.data["id"]).to_dict()
        self.assertEqual((doc["lat"], doc["lng"]), (51.5074, -0.1278))
        self.assertEqual(doc["timezone"], "Europe/London")
        self.assertEqual(doc["owner_key"], "owner-a")
        self.assertNotIn("last_contact_channel", doc)

    def test_preferred_airport_and_station_are_expanded(self, _geocode):
        response = self.client.post(
            "/api/people/",
            {**PERSON_PAYLOAD, "preferred_airport": 1, "preferred_station": 1},
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        props = response.data["properties"]
        self.assertEqual(props["preferred_airport"], 1)
        self.assertEqual(
            props["preferred_airport_detail"]["properties"]["iata_code"], "AAA"
        )
        self.assertEqual(props["preferred_station"], 1)
        self.assertEqual(
            props["preferred_station_detail"]["properties"]["name"], "1st Street"
        )

    def test_invalid_payloads_are_400_and_write_nothing(self, geocode):
        cases = {
            "tag": {k: v for k, v in PERSON_PAYLOAD.items() if k != "tag"},
            "tag_choice": {**PERSON_PAYLOAD, "tag": "COLLEAGUE"},
            "pin_style": {**PERSON_PAYLOAD, "pin_style": "hexagon"},
            "pin_icon_type": {**PERSON_PAYLOAD, "pin_icon_type": "svg"},
            "contact_cadence_days": {**PERSON_PAYLOAD, "contact_cadence_days": -1},
            "first_name": {**PERSON_PAYLOAD, "first_name": "x" * 101},
            "pin_emoji": {**PERSON_PAYLOAD, "pin_emoji": "x" * 11},
            "birthday": {**PERSON_PAYLOAD, "birthday": "02/01/1990"},
            "preferred_airport": {**PERSON_PAYLOAD, "preferred_airport": 10**9},
            "preferred_station": {**PERSON_PAYLOAD, "preferred_station": 10**9},
        }
        for case, payload in cases.items():
            with self.subTest(case):
                response = self.client.post("/api/people/", payload, format="json")
                self.assertEqual(response.status_code, 400)
                field = case.removesuffix("_choice")
                self.assertIn(field, response.data)

        geocode.assert_not_called()
        self.assertEqual(self.people.list_for_owner("owner-a"), [])

    def test_unknown_reference_ids_report_a_specific_message(self, _geocode):
        response = self.client.post(
            "/api/people/",
            {**PERSON_PAYLOAD, "preferred_airport": 10**9, "preferred_station": 10**9},
            format="json",
        )
        self.assertEqual(response.data["preferred_airport"], ["Unknown airport id."])
        self.assertEqual(response.data["preferred_station"], ["Unknown station id."])


@patch("apps.people.views.geocode_address", return_value=PARIS)
class PersonUpdateTests(PersonTestCase):
    def setUp(self):
        super().setUp()
        self.person = self.people.create(
            "owner-a", {**SEEDED_PERSON, "timezone": "Europe/London"}
        )
        self.url = f"/api/people/{self.person.id}/"
        self.client.force_authenticate(user=self.user)

    def test_put_replaces_fields_and_regeocodes(self, geocode):
        response = self.client.put(
            self.url,
            {
                "tag": "FAMILY",
                "first_name": "Marie",
                "last_name": "Curie",
                "city": "Paris",
                "state": "Île-de-France",
                "country": "France",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        geocode.assert_called_once_with("Paris", "Île-de-France", "France", None)
        self.assertEqual(response.data["geometry"]["coordinates"], [PARIS[1], PARIS[0]])
        doc = stored(self.person.id).to_dict()
        self.assertEqual(doc["first_name"], "Marie")
        self.assertEqual(doc["tag"], "FAMILY")
        self.assertEqual(doc["timezone"], "Europe/Paris")
        self.assertEqual(doc["owner_key"], "owner-a")

    def test_put_requires_the_full_payload(self, geocode):
        response = self.client.put(self.url, {"first_name": "Marie"}, format="json")

        self.assertEqual(response.status_code, 400)
        self.assertIn("tag", response.data)
        geocode.assert_not_called()
        self.assertEqual(stored(self.person.id).to_dict()["first_name"], "Ada")

    def test_patch_without_address_fields_skips_geocoding(self, geocode):
        response = self.client.patch(self.url, {"first_name": "Augusta"}, format="json")

        self.assertEqual(response.status_code, 200)
        geocode.assert_not_called()
        self.assertEqual(response.data["properties"]["first_name"], "Augusta")
        doc = stored(self.person.id).to_dict()
        self.assertEqual(doc["first_name"], "Augusta")
        # Untouched fields, coordinates included, survive a partial update.
        self.assertEqual(doc["last_name"], "Lovelace")
        self.assertEqual((doc["lat"], doc["lng"]), (51.5074, -0.1278))
        self.assertEqual(doc["timezone"], "Europe/London")

    def test_patch_with_an_address_field_regeocodes(self, geocode):
        for field in ("city", "state", "country", "street"):
            with self.subTest(field):
                geocode.reset_mock()
                response = self.client.patch(self.url, {field: "X"}, format="json")

                self.assertEqual(response.status_code, 200)
                geocode.assert_called_once()
                doc = stored(self.person.id).to_dict()
                self.assertEqual((doc["lat"], doc["lng"]), (PARIS[0], PARIS[1]))
                self.assertEqual(doc["timezone"], "Europe/Paris")

    def test_patch_bumps_updated_at(self, _geocode):
        before = stored(self.person.id).to_dict()["updated_at"]
        self.client.patch(self.url, {"first_name": "Augusta"}, format="json")
        self.assertGreater(stored(self.person.id).to_dict()["updated_at"], before)

    def test_patch_serializes_birthday_for_firestore(self, _geocode):
        response = self.client.patch(
            self.url, {"birthday": "1815-12-10T00:00:00.000"}, format="json"
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["properties"]["birthday"], "1815-12-10")
        self.assertEqual(stored(self.person.id).to_dict()["birthday"], "1815-12-10")

    def test_patch_can_clear_nullable_fields(self, _geocode):
        self.people.update(
            self.person.id, "owner-a", {"phone_number": "123", "preferred_airport": 1}
        )

        response = self.client.patch(
            self.url,
            {"phone_number": None, "preferred_airport": None},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        props = response.data["properties"]
        self.assertIsNone(props["phone_number"])
        self.assertIsNone(props["preferred_airport"])
        self.assertIsNone(props["preferred_airport_detail"])

    def test_patch_invalid_value_is_400_and_writes_nothing(self, _geocode):
        response = self.client.patch(self.url, {"pin_style": "blob"}, format="json")

        self.assertEqual(response.status_code, 400)
        self.assertIn("pin_style", response.data)
        # Pin defaults are applied on read, so the field was never written.
        self.assertNotIn("pin_style", stored(self.person.id).to_dict())

    def test_patch_cannot_change_owner(self, _geocode):
        self.client.patch(self.url, {"owner": "owner-b"}, format="json")
        self.assertEqual(stored(self.person.id).to_dict()["owner_key"], "owner-a")

    def test_update_unknown_id_is_404(self, _geocode):
        for method in (self.client.put, self.client.patch):
            with self.subTest(method.__name__):
                response = method(
                    "/api/people/does-not-exist/", PERSON_PAYLOAD, format="json"
                )
                self.assertEqual(response.status_code, 404)
        self.assertFalse(stored("does-not-exist").exists)

    def test_update_another_owners_person_is_404_and_writes_nothing(self, _geocode):
        self.client.force_authenticate(user=self.other)

        response = self.client.patch(self.url, {"first_name": "Mallory"}, format="json")

        self.assertEqual(response.status_code, 404)
        self.assertEqual(stored(self.person.id).to_dict()["first_name"], "Ada")

    def test_update_requires_auth(self, _geocode):
        self.client.force_authenticate(user=None)
        response = self.client.patch(self.url, {"first_name": "Eve"}, format="json")
        self.assertEqual(response.status_code, 401)


@patch("apps.people.views.geocode_address", return_value=LONDON)
class PersonDestroyTests(PersonTestCase):
    def test_delete_removes_person_and_their_contact_logs(self, _geocode):
        person = self.people.create("owner-a", SEEDED_PERSON)
        ContactLogRepository().create(
            "owner-a",
            person.id,
            {"channel": "CALL", "contacted_at": "2026-07-01T12:00:00+00:00"},
        )
        self.client.force_authenticate(user=self.user)

        response = self.client.delete(f"/api/people/{person.id}/")

        self.assertEqual(response.status_code, 204)
        self.assertFalse(stored(person.id).exists)
        # Firestore does not cascade deletes, so orphaned logs would otherwise
        # linger under the deleted person's path.
        logs = fs.collection("people").document(person.id).collection("contact_logs")
        self.assertEqual(list(logs.stream()), [])

    def test_delete_unknown_id_is_404(self, _geocode):
        self.client.force_authenticate(user=self.user)
        response = self.client.delete("/api/people/does-not-exist/")
        self.assertEqual(response.status_code, 404)

    def test_delete_requires_auth(self, _geocode):
        person = self.people.create(None, SEEDED_PERSON)
        response = self.client.delete(f"/api/people/{person.id}/")
        self.assertEqual(response.status_code, 401)
        self.assertTrue(stored(person.id).exists)


class PersonGeocodingFailureTests(PersonTestCase):
    """geocode_address raises Django's ValidationError, which DRF does not
    handle; unmapped, both failure modes used to surface as a 500."""

    NOT_FOUND = ValidationError("Could not geocode address: Nowhere")
    OUTAGE = GeocodingUnavailable(
        "Geocoding service unavailable. Please try again later."
    )

    def setUp(self):
        super().setUp()
        self.person = self.people.create("owner-a", SEEDED_PERSON)
        self.url = f"/api/people/{self.person.id}/"
        self.client.force_authenticate(user=self.user)

    def write(self, method, side_effect):
        requests = {
            "create": lambda: self.client.post(
                "/api/people/", PERSON_PAYLOAD, format="json"
            ),
            "patch": lambda: self.client.patch(
                self.url, {"city": "Nowhere"}, format="json"
            ),
        }
        with patch("apps.people.views.geocode_address", side_effect=side_effect):
            return requests[method]()

    def assert_nothing_written(self):
        self.assertEqual(
            [p.id for p in self.people.list_for_owner("owner-a")], [self.person.id]
        )
        self.assertEqual(stored(self.person.id).to_dict()["city"], "London")

    def test_unresolvable_address_is_400(self):
        for method in ("create", "patch"):
            with self.subTest(method):
                response = self.write(method, self.NOT_FOUND)

                self.assertEqual(response.status_code, 400)
                self.assertEqual(
                    response.data,
                    {"non_field_errors": ["Could not geocode address: Nowhere"]},
                )
                self.assert_nothing_written()

    def test_geocoder_outage_is_503(self):
        for method in ("create", "patch"):
            with self.subTest(method):
                response = self.write(method, self.OUTAGE)

                self.assertEqual(response.status_code, 503)
                self.assertEqual(
                    response.data,
                    {"error": "Geocoding service unavailable. Please try again later."},
                )
                self.assert_nothing_written()


@patch("apps.people.views.geocode_address", return_value=LONDON)
class PersonReservedIdTests(PersonTestCase):
    """The router keeps "/" and "." out of URL ids, but not Firestore-reserved
    __names__, which Firestore rejects outright rather than reporting missing."""

    def test_reserved_ids_are_404(self, _geocode):
        self.client.force_authenticate(user=self.user)
        url = "/api/people/__reserved__/"
        requests = {
            "retrieve": lambda: self.client.get(url),
            "update": lambda: self.client.put(url, PERSON_PAYLOAD, format="json"),
            "partial_update": lambda: self.client.patch(
                url, {"first_name": "X"}, format="json"
            ),
            "destroy": lambda: self.client.delete(url),
        }
        for action, request in requests.items():
            with self.subTest(action):
                self.assertEqual(request().status_code, 404)


@patch("apps.people.views.geocode_address", return_value=LONDON)
class PersonProfileImageTests(PersonTestCase):
    """Multipart uploads go through default_storage, pointed at a temp dir."""

    def setUp(self):
        super().setUp()
        self.media_root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.media_root, ignore_errors=True)
        settings_override = override_settings(MEDIA_ROOT=self.media_root)
        settings_override.enable()
        self.addCleanup(settings_override.disable)
        self.client.force_authenticate(user=self.user)

    @staticmethod
    def image(name="avatar.png"):
        return SimpleUploadedFile(name, b"\x89PNG\r\n\x1a\n", content_type="image/png")

    def test_multipart_create_stores_the_image(self, _geocode):
        response = self.client.post(
            "/api/people/",
            {**PERSON_PAYLOAD, "profile_image": self.image()},
            format="multipart",
        )

        self.assertEqual(response.status_code, 201)
        name = stored(response.data["id"]).to_dict()["profile_image"]
        self.assertRegex(name, r"^profile_images/[0-9a-f]{32}\.png$")
        self.assertTrue(default_storage.exists(name))
        self.assertEqual(
            response.data["properties"]["profile_image"],
            f"http://testserver/media/{name}",
        )

    def test_multipart_patch_replaces_the_image(self, _geocode):
        created = self.client.post(
            "/api/people/",
            {**PERSON_PAYLOAD, "profile_image": self.image()},
            format="multipart",
        )
        first = stored(created.data["id"]).to_dict()["profile_image"]

        response = self.client.patch(
            f"/api/people/{created.data['id']}/",
            {"profile_image": self.image("Portrait.JPG")},
            format="multipart",
        )

        self.assertEqual(response.status_code, 200)
        second = stored(created.data["id"]).to_dict()["profile_image"]
        self.assertNotEqual(first, second)
        # Extensions are normalised to lower case.
        self.assertTrue(second.endswith(".jpg"))
        self.assertTrue(response.data["properties"]["profile_image"].endswith(second))

    def test_multipart_create_without_image_leaves_it_unset(self, _geocode):
        response = self.client.post("/api/people/", PERSON_PAYLOAD, format="multipart")

        self.assertEqual(response.status_code, 201)
        self.assertIsNone(response.data["properties"]["profile_image"])
        self.assertNotIn("profile_image", stored(response.data["id"]).to_dict())
