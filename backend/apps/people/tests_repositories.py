from django.test import SimpleTestCase

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


class PersonRepositoryTests(FirestoreTestMixin, SimpleTestCase):
    collections_to_purge = ["people"]

    def setUp(self):
        super().setUp()
        self.people = PersonRepository()

    def test_create_assigns_string_id(self):
        person = self.people.create("owner-a", PERSON_DATA)
        self.assertIsInstance(person.id, str)
        self.assertTrue(person.id)

    def test_create_sets_owner_key(self):
        person = self.people.create("owner-a", PERSON_DATA)
        self.assertEqual(person.owner_key, "owner-a")

    def test_list_returns_only_own_people(self):
        self.people.create("owner-a", PERSON_DATA)
        self.people.create("owner-b", PERSON_DATA)
        self.assertEqual(len(self.people.list_for_owner("owner-a")), 1)

    def test_list_for_none_owner_returns_public_people(self):
        self.people.create(None, PERSON_DATA)
        self.people.create("owner-a", PERSON_DATA)
        public = self.people.list_for_owner(None)
        self.assertEqual(len(public), 1)
        self.assertIsNone(public[0].owner_key)

    def test_get_for_wrong_owner_returns_none(self):
        person = self.people.create("owner-a", PERSON_DATA)
        self.assertIsNone(self.people.get_for_owner(person.id, "owner-b"))

    def test_get_for_correct_owner_returns_record(self):
        person = self.people.create("owner-a", PERSON_DATA)
        self.assertEqual(self.people.get_for_owner(person.id, "owner-a").id, person.id)

    def test_update_applies_changes(self):
        person = self.people.create("owner-a", PERSON_DATA)
        updated = self.people.update(person.id, "owner-a", {"first_name": "Grace"})
        self.assertEqual(updated.first_name, "Grace")

    def test_update_by_wrong_owner_returns_none(self):
        person = self.people.create("owner-a", PERSON_DATA)
        self.assertIsNone(
            self.people.update(person.id, "owner-b", {"first_name": "Nope"})
        )

    def test_delete_removes_document(self):
        person = self.people.create("owner-a", PERSON_DATA)
        self.assertTrue(self.people.delete(person.id, "owner-a"))
        self.assertIsNone(self.people.get_for_owner(person.id, "owner-a"))

    def test_delete_by_wrong_owner_is_refused(self):
        person = self.people.create("owner-a", PERSON_DATA)
        self.assertFalse(self.people.delete(person.id, "owner-b"))
        self.assertIsNotNone(self.people.get_for_owner(person.id, "owner-a"))


class ContactLogRepositoryTests(FirestoreTestMixin, SimpleTestCase):
    collections_to_purge = ["people"]

    def setUp(self):
        super().setUp()
        self.people = PersonRepository()
        self.logs = ContactLogRepository()
        self.person_a = self.people.create("owner-a", PERSON_DATA)
        self.person_b = self.people.create("owner-b", PERSON_DATA)

    def test_create_log_for_own_person(self):
        log = self.logs.create(
            "owner-a",
            self.person_a.id,
            {"channel": "CALL", "contacted_at": "2026-07-01T12:00:00+00:00"},
        )
        self.assertEqual(log.person_id, self.person_a.id)

    def test_cannot_create_log_for_another_owners_person(self):
        log = self.logs.create(
            "owner-a",
            self.person_b.id,
            {"channel": "CALL", "contacted_at": "2026-07-01T12:00:00+00:00"},
        )
        self.assertIsNone(log)

    def test_list_is_scoped_to_owner(self):
        self.logs.create(
            "owner-a",
            self.person_a.id,
            {"channel": "CALL", "contacted_at": "2026-07-01T12:00:00+00:00"},
        )
        self.logs.create(
            "owner-b",
            self.person_b.id,
            {"channel": "VIDEO", "contacted_at": "2026-07-02T12:00:00+00:00"},
        )
        self.assertEqual(len(self.logs.list_for_owner("owner-a")), 1)

    def test_person_filter_scoped_to_owner(self):
        self.logs.create(
            "owner-a",
            self.person_a.id,
            {"channel": "CALL", "contacted_at": "2026-07-01T12:00:00+00:00"},
        )
        # Filtering by another owner's person yields nothing, not a leak.
        self.assertEqual(
            self.logs.list_for_owner("owner-a", person_id=self.person_b.id), []
        )

    def test_logs_ordered_most_recent_first(self):
        self.logs.create(
            "owner-a",
            self.person_a.id,
            {"channel": "CALL", "contacted_at": "2026-07-01T12:00:00+00:00"},
        )
        self.logs.create(
            "owner-a",
            self.person_a.id,
            {"channel": "VIDEO", "contacted_at": "2026-07-05T12:00:00+00:00"},
        )
        logs = self.logs.list_for_owner("owner-a", person_id=self.person_a.id)
        self.assertEqual(logs[0].channel, "VIDEO")

    def test_person_carries_recency_summary(self):
        self.logs.create(
            "owner-a",
            self.person_a.id,
            {"channel": "VIDEO", "contacted_at": "2026-07-05T12:00:00+00:00"},
        )
        person = self.people.get_for_owner(self.person_a.id, "owner-a")
        self.assertEqual(person.last_contact_channel, "VIDEO")
        self.assertTrue(person.last_contacted_at.startswith("2026-07-05"))


class OwnershipReassignmentTests(FirestoreTestMixin, SimpleTestCase):
    """owner_key must never be writable from caller-supplied data.

    The serializer marks it read-only, but the repository is the security
    boundary in its own right: a caller passing {"owner_key": ...} must not be
    able to claim another owner's record or hand away their own.
    """

    collections_to_purge = ["people"]

    def setUp(self):
        super().setUp()
        self.people = PersonRepository()

    def test_create_ignores_owner_key_in_data(self):
        person = self.people.create("owner-a", {**PERSON_DATA, "owner_key": "owner-b"})
        self.assertEqual(person.owner_key, "owner-a")

    def test_update_cannot_reassign_ownership(self):
        person = self.people.create("owner-a", PERSON_DATA)
        self.people.update(person.id, "owner-a", {"owner_key": "owner-b"})

        # Still owned by owner-a, and never visible to owner-b.
        self.assertEqual(
            self.people.get_for_owner(person.id, "owner-a").owner_key, "owner-a"
        )
        self.assertIsNone(self.people.get_for_owner(person.id, "owner-b"))

    def test_update_cannot_make_record_public(self):
        person = self.people.create("owner-a", PERSON_DATA)
        self.people.update(person.id, "owner-a", {"owner_key": None})
        self.assertEqual(self.people.list_for_owner(None), [])


class ContactLogCrossOwnerTests(FirestoreTestMixin, SimpleTestCase):
    """get/update/delete on logs must refuse another owner, not just create."""

    collections_to_purge = ["people"]

    def setUp(self):
        super().setUp()
        self.people = PersonRepository()
        self.logs = ContactLogRepository()
        self.person_a = self.people.create("owner-a", PERSON_DATA)
        self.log_a = self.logs.create(
            "owner-a",
            self.person_a.id,
            {"channel": "CALL", "contacted_at": "2026-07-01T12:00:00+00:00"},
        )

    def test_get_for_wrong_owner_returns_none(self):
        self.assertIsNone(self.logs.get_for_owner(self.log_a.id, "owner-b"))

    def test_update_by_wrong_owner_returns_none_and_does_not_write(self):
        self.assertIsNone(
            self.logs.update(self.log_a.id, "owner-b", {"channel": "VIDEO"})
        )
        self.assertEqual(
            self.logs.get_for_owner(self.log_a.id, "owner-a").channel, "CALL"
        )

    def test_delete_by_wrong_owner_is_refused(self):
        self.assertFalse(self.logs.delete(self.log_a.id, "owner-b"))
        self.assertIsNotNone(self.logs.get_for_owner(self.log_a.id, "owner-a"))


class PersonDeleteCascadeTests(FirestoreTestMixin, SimpleTestCase):
    collections_to_purge = ["people"]

    def test_delete_removes_contact_log_subcollection(self):
        people = PersonRepository()
        logs = ContactLogRepository()
        person = people.create("owner-a", PERSON_DATA)
        for day in (1, 2):
            logs.create(
                "owner-a",
                person.id,
                {"channel": "CALL", "contacted_at": f"2026-07-0{day}T12:00:00+00:00"},
            )

        self.assertTrue(people.delete(person.id, "owner-a"))

        # Firestore leaves subcollections behind when a parent is deleted, so
        # the repository must remove them itself.
        remaining = (
            fs.collection("people")
            .document(person.id)
            .collection("contact_logs")
            .stream()
        )
        self.assertEqual(list(remaining), [])


class ContactLogWriteTests(FirestoreTestMixin, SimpleTestCase):
    collections_to_purge = ["people"]

    def setUp(self):
        super().setUp()
        self.people = PersonRepository()
        self.logs = ContactLogRepository()
        self.person = self.people.create("owner-a", PERSON_DATA)
        self.log = self.logs.create(
            "owner-a",
            self.person.id,
            {
                "channel": "CALL",
                "contacted_at": "2026-07-01T12:00:00+00:00",
                "note": "First",
            },
        )

    def raw(self):
        return (
            fs.collection("people")
            .document(self.person.id)
            .collection("contact_logs")
            .document(self.log.id)
            .get()
        )

    def test_get_for_owner_returns_record(self):
        record = self.logs.get_for_owner(self.log.id, "owner-a")
        self.assertEqual(record.id, self.log.id)
        self.assertEqual(record.person_id, self.person.id)
        self.assertEqual(record.note, "First")

    def test_get_unknown_id_returns_none(self):
        self.assertIsNone(self.logs.get_for_owner("does-not-exist", "owner-a"))

    def test_update_applies_changes(self):
        updated = self.logs.update(
            self.log.id, "owner-a", {"channel": "VIDEO", "note": "Edited"}
        )

        self.assertEqual(updated.channel, "VIDEO")
        self.assertEqual(updated.note, "Edited")
        self.assertEqual(updated.person_id, self.person.id)
        self.assertEqual(self.raw().to_dict()["channel"], "VIDEO")

    def test_update_ignores_non_writable_keys(self):
        self.logs.update(
            self.log.id,
            "owner-a",
            {"note": "Edited", "created_at": "1970-01-01", "person_id": "other"},
        )

        doc = self.raw().to_dict()
        self.assertEqual(doc["note"], "Edited")
        self.assertNotEqual(doc["created_at"], "1970-01-01")
        self.assertNotIn("person_id", doc)

    def test_update_with_nothing_writable_is_a_no_op(self):
        # Firestore rejects an empty update, so this must short-circuit.
        updated = self.logs.update(self.log.id, "owner-a", {"unknown": "x"})
        self.assertEqual(updated.note, "First")
        self.assertEqual(updated.channel, "CALL")

    def test_update_unknown_id_returns_none(self):
        self.assertIsNone(self.logs.update("does-not-exist", "owner-a", {"note": "x"}))

    def test_delete_removes_document(self):
        self.assertTrue(self.logs.delete(self.log.id, "owner-a"))
        self.assertFalse(self.raw().exists)
        self.assertIsNone(self.logs.get_for_owner(self.log.id, "owner-a"))

    def test_delete_unknown_id_returns_false(self):
        self.assertFalse(self.logs.delete("does-not-exist", "owner-a"))
        self.assertTrue(self.raw().exists)


class InvalidIdTests(FirestoreTestMixin, SimpleTestCase):
    """Ids Firestore cannot address directly are treated as not found."""

    collections_to_purge = ["people"]
    INVALID_IDS = ("", "x/y", ".", "..", "__x__")

    def setUp(self):
        super().setUp()
        self.people = PersonRepository()
        self.logs = ContactLogRepository()

    def test_person_methods_report_not_found(self):
        for person_id in self.INVALID_IDS:
            with self.subTest(person_id):
                self.assertIsNone(self.people.get_for_owner(person_id, "owner-a"))
                self.assertIsNone(
                    self.people.update(person_id, "owner-a", {"first_name": "X"})
                )
                self.assertFalse(self.people.delete(person_id, "owner-a"))

    def test_contact_log_methods_report_not_found(self):
        log = {"channel": "CALL", "contacted_at": "2026-07-01T12:00:00+00:00"}
        for person_id in self.INVALID_IDS:
            with self.subTest(person_id):
                self.assertIsNone(self.logs.create("owner-a", person_id, log))
                self.assertEqual(
                    self.logs.list_for_owner("owner-a", person_id=person_id), []
                )

    def test_nested_path_cannot_reach_a_contact_log_document(self):
        # "people/{id}/contact_logs/{log}" is a valid document path; it must
        # not be accepted as a person id.
        person = self.people.create(None, PERSON_DATA)
        log = self.logs.create(
            None,
            person.id,
            {"channel": "CALL", "contacted_at": "2026-07-01T12:00:00+00:00"},
        )
        nested = f"{person.id}/contact_logs/{log.id}"
        self.assertIsNone(self.people.get_for_owner(nested, None))
        self.assertIsNone(
            self.logs.create(None, nested, {"channel": "CALL", "contacted_at": "x"})
        )
