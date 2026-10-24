"""Functional tests for /api/contact-logs/ (ContactLogViewSet).

Cross-owner isolation is covered in tests.py and tests/test_api_security.py;
these cover each action's behaviour against the emulator.
"""

from django.contrib.auth.models import User
from rest_framework.test import APITestCase

from apps.common import firestore as fs
from apps.common.testing import FirestoreTestMixin
from apps.people.repositories import ContactLogRepository, PersonRepository

PERSON_DATA = {
    "tag": "FRIEND",
    "first_name": "Ada",
    "last_name": "Lovelace",
    "city": "London",
    "state": "England",
    "country": "UK",
    "lat": 51.5074,
    "lng": -0.1278,
}

LOG_PAYLOAD = {"channel": "CALL", "contacted_at": "2026-07-01T12:00:00Z"}


def stored_log(person_id, log_id):
    """The raw Firestore log document, bypassing the repository."""
    return (
        fs.collection("people")
        .document(person_id)
        .collection("contact_logs")
        .document(log_id)
        .get()
    )


class ContactLogTestCase(FirestoreTestMixin, APITestCase):
    collections_to_purge = ["people"]

    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(username="owner-a", password="pw12345!")
        self.client.force_authenticate(user=self.user)

        self.people = PersonRepository()
        self.logs = ContactLogRepository()
        self.ada = self.people.create("owner-a", PERSON_DATA)
        self.grace = self.people.create(
            "owner-a", {**PERSON_DATA, "first_name": "Grace"}
        )

    def seed_log(self, person, **data):
        return self.logs.create("owner-a", person.id, {**LOG_PAYLOAD, **data})


class ContactLogListTests(ContactLogTestCase):
    def test_empty_list(self):
        response = self.client.get("/api/contact-logs/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, [])

    def test_lists_logs_across_people_most_recent_first(self):
        oldest = self.seed_log(self.ada, contacted_at="2026-07-01T09:00:00+00:00")
        newest = self.seed_log(self.grace, contacted_at="2026-07-03T09:00:00+00:00")
        middle = self.seed_log(self.ada, contacted_at="2026-07-02T09:00:00+00:00")

        response = self.client.get("/api/contact-logs/")

        self.assertEqual(
            [log["id"] for log in response.data], [newest.id, middle.id, oldest.id]
        )
        self.assertEqual(
            [log["person"] for log in response.data],
            [self.grace.id, self.ada.id, self.ada.id],
        )

    def test_person_filter_scopes_to_that_person(self):
        ada_log = self.seed_log(self.ada, contacted_at="2026-07-01T09:00:00+00:00")
        self.seed_log(self.grace, contacted_at="2026-07-02T09:00:00+00:00")

        response = self.client.get("/api/contact-logs/", {"person": self.ada.id})

        self.assertEqual([log["id"] for log in response.data], [ada_log.id])

    def test_person_filter_for_unknown_person_is_empty(self):
        self.seed_log(self.ada, contacted_at="2026-07-01T09:00:00+00:00")
        response = self.client.get("/api/contact-logs/", {"person": "nobody"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, [])


class ContactLogRetrieveTests(ContactLogTestCase):
    def test_retrieve_returns_the_log(self):
        log = self.seed_log(
            self.ada, contacted_at="2026-07-01T12:00:00+00:00", note="Caught up"
        )

        response = self.client.get(f"/api/contact-logs/{log.id}/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["id"], log.id)
        self.assertEqual(response.data["person"], self.ada.id)
        self.assertEqual(response.data["channel"], "CALL")
        self.assertEqual(response.data["contacted_at"], "2026-07-01T12:00:00+00:00")
        self.assertEqual(response.data["note"], "Caught up")
        self.assertIsNotNone(response.data["created_at"])

    def test_unknown_id_is_404(self):
        response = self.client.get("/api/contact-logs/does-not-exist/")
        self.assertEqual(response.status_code, 404)


class ContactLogCreateTests(ContactLogTestCase):
    def test_create_persists_under_the_person(self):
        response = self.client.post(
            "/api/contact-logs/",
            {**LOG_PAYLOAD, "person": self.ada.id, "note": "Birthday call"},
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["person"], self.ada.id)
        self.assertEqual(response.data["note"], "Birthday call")
        doc = stored_log(self.ada.id, response.data["id"])
        self.assertTrue(doc.exists)
        self.assertEqual(doc.to_dict()["channel"], "CALL")
        self.assertEqual(doc.to_dict()["note"], "Birthday call")
        self.assertIn("created_at", doc.to_dict())

    def test_contacted_at_is_normalised_to_utc(self):
        # Logs sort by contacted_at as a string, so every stored value must
        # share an offset for the ordering to be chronological.
        response = self.client.post(
            "/api/contact-logs/",
            {
                "person": self.ada.id,
                "channel": "VIDEO",
                "contacted_at": "2026-07-01T12:00:00+02:00",
            },
            format="json",
        )

        doc = stored_log(self.ada.id, response.data["id"]).to_dict()
        self.assertEqual(doc["contacted_at"], "2026-07-01T10:00:00+00:00")

    def test_note_is_optional(self):
        response = self.client.post(
            "/api/contact-logs/",
            {**LOG_PAYLOAD, "person": self.ada.id},
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertIsNone(response.data["note"])

    def test_create_updates_the_persons_recency_summary(self):
        self.seed_log(self.ada, contacted_at="2026-07-01T09:00:00+00:00")
        self.client.post(
            "/api/contact-logs/",
            {
                "person": self.ada.id,
                "channel": "MESSAGE",
                "contacted_at": "2026-07-09T09:00:00Z",
            },
            format="json",
        )

        props = self.client.get(f"/api/people/{self.ada.id}/").data["properties"]

        self.assertEqual(props["last_contact_channel"], "MESSAGE")
        self.assertTrue(props["last_contacted_at"].startswith("2026-07-09"))

    def test_unknown_person_is_400(self):
        response = self.client.post(
            "/api/contact-logs/",
            {**LOG_PAYLOAD, "person": "nobody"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data, {"person": ["Invalid person."]})

    def test_invalid_payloads_are_400_and_write_nothing(self):
        valid = {**LOG_PAYLOAD, "person": self.ada.id}
        cases = {
            "person": {k: v for k, v in valid.items() if k != "person"},
            "channel": {**valid, "channel": "EMAIL"},
            "contacted_at": {**valid, "contacted_at": "yesterday"},
            "note": {**valid, "note": "x" * 281},
        }
        for field, payload in cases.items():
            with self.subTest(field):
                response = self.client.post(
                    "/api/contact-logs/", payload, format="json"
                )
                self.assertEqual(response.status_code, 400)
                self.assertIn(field, response.data)

        self.assertEqual(self.logs.list_for_owner("owner-a"), [])


class ContactLogUpdateTests(ContactLogTestCase):
    def setUp(self):
        super().setUp()
        self.log = self.seed_log(
            self.ada, contacted_at="2026-07-01T12:00:00+00:00", note="First"
        )
        self.url = f"/api/contact-logs/{self.log.id}/"

    def test_put_replaces_the_log(self):
        response = self.client.put(
            self.url,
            {
                "person": self.ada.id,
                "channel": "VIDEO",
                "contacted_at": "2026-07-05T08:30:00Z",
                "note": "Rescheduled",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["channel"], "VIDEO")
        doc = stored_log(self.ada.id, self.log.id).to_dict()
        self.assertEqual(doc["channel"], "VIDEO")
        self.assertEqual(doc["contacted_at"], "2026-07-05T08:30:00+00:00")
        self.assertEqual(doc["note"], "Rescheduled")

    def test_put_requires_the_full_payload(self):
        response = self.client.put(self.url, {"note": "Only a note"}, format="json")

        self.assertEqual(response.status_code, 400)
        for field in ("person", "channel", "contacted_at"):
            self.assertIn(field, response.data)
        self.assertEqual(
            stored_log(self.ada.id, self.log.id).to_dict()["note"], "First"
        )

    def test_put_does_not_move_the_log_to_another_person(self):
        response = self.client.put(
            self.url,
            {**LOG_PAYLOAD, "person": self.grace.id},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["person"], self.ada.id)
        self.assertTrue(stored_log(self.ada.id, self.log.id).exists)
        self.assertFalse(stored_log(self.grace.id, self.log.id).exists)

    def test_patch_updates_only_the_given_field(self):
        response = self.client.patch(self.url, {"note": "Edited"}, format="json")

        self.assertEqual(response.status_code, 200)
        doc = stored_log(self.ada.id, self.log.id).to_dict()
        self.assertEqual(doc["note"], "Edited")
        self.assertEqual(doc["channel"], "CALL")
        self.assertEqual(doc["contacted_at"], "2026-07-01T12:00:00+00:00")

    def test_patch_normalises_contacted_at_to_utc(self):
        self.client.patch(
            self.url, {"contacted_at": "2026-07-02T09:00:00-05:00"}, format="json"
        )
        doc = stored_log(self.ada.id, self.log.id).to_dict()
        self.assertEqual(doc["contacted_at"], "2026-07-02T14:00:00+00:00")

    def test_patch_can_clear_the_note(self):
        response = self.client.patch(self.url, {"note": None}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertIsNone(stored_log(self.ada.id, self.log.id).to_dict()["note"])

    def test_empty_patch_is_a_no_op(self):
        response = self.client.patch(self.url, {}, format="json")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["note"], "First")
        self.assertEqual(response.data["channel"], "CALL")

    def test_patch_invalid_value_is_400_and_writes_nothing(self):
        response = self.client.patch(self.url, {"channel": "FAX"}, format="json")

        self.assertEqual(response.status_code, 400)
        self.assertIn("channel", response.data)
        self.assertEqual(
            stored_log(self.ada.id, self.log.id).to_dict()["channel"], "CALL"
        )

    def test_update_unknown_id_is_404(self):
        for method in (self.client.put, self.client.patch):
            with self.subTest(method.__name__):
                response = method(
                    "/api/contact-logs/does-not-exist/",
                    {**LOG_PAYLOAD, "person": self.ada.id},
                    format="json",
                )
                self.assertEqual(response.status_code, 404)

    def test_update_requires_auth(self):
        self.client.force_authenticate(user=None)
        response = self.client.patch(self.url, {"note": "Anon"}, format="json")
        self.assertEqual(response.status_code, 401)


class ContactLogDestroyTests(ContactLogTestCase):
    def test_delete_removes_the_log(self):
        log = self.seed_log(self.ada, contacted_at="2026-07-01T12:00:00+00:00")

        response = self.client.delete(f"/api/contact-logs/{log.id}/")

        self.assertEqual(response.status_code, 204)
        self.assertFalse(stored_log(self.ada.id, log.id).exists)
        # The person itself is untouched.
        self.assertIsNotNone(self.people.get_for_owner(self.ada.id, "owner-a"))

    def test_deleting_the_latest_log_rolls_back_recency(self):
        self.seed_log(
            self.ada, channel="CALL", contacted_at="2026-07-01T09:00:00+00:00"
        )
        latest = self.seed_log(
            self.ada, channel="VIDEO", contacted_at="2026-07-05T09:00:00+00:00"
        )

        self.client.delete(f"/api/contact-logs/{latest.id}/")

        props = self.client.get(f"/api/people/{self.ada.id}/").data["properties"]
        self.assertEqual(props["last_contact_channel"], "CALL")
        self.assertTrue(props["last_contacted_at"].startswith("2026-07-01"))

    def test_delete_unknown_id_is_404(self):
        response = self.client.delete("/api/contact-logs/does-not-exist/")
        self.assertEqual(response.status_code, 404)

    def test_delete_requires_auth(self):
        log = self.seed_log(self.ada, contacted_at="2026-07-01T12:00:00+00:00")
        self.client.force_authenticate(user=None)

        response = self.client.delete(f"/api/contact-logs/{log.id}/")

        self.assertEqual(response.status_code, 401)
        self.assertTrue(stored_log(self.ada.id, log.id).exists)
