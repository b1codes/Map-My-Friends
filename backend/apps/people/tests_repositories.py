import threading
from unittest.mock import patch

from django.test import SimpleTestCase
from google.api_core.exceptions import AlreadyExists, FailedPrecondition
from google.cloud.firestore_v1.collection import CollectionReference

from apps.common import firestore as fs
from apps.common.testing import FirestoreTestMixin
from apps.people.repositories import (
    DELETE_ATTEMPTS,
    ContactLogRepository,
    PersonRepository,
)

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

    def test_create_with_an_id_stores_it_only_once(self):
        person = self.people.create("owner-a", PERSON_DATA, person_id="fixed-id")
        self.assertEqual(person.id, "fixed-id")

        with self.assertRaises(AlreadyExists):
            self.people.create(
                "owner-a", {**PERSON_DATA, "first_name": "Augusta"}, "fixed-id"
            )
        self.assertEqual(self.people.get_for_owner("fixed-id", "owner-a"), person)

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


class GetManyForOwnerTests(FirestoreTestMixin, SimpleTestCase):
    collections_to_purge = ["people"]

    def setUp(self):
        super().setUp()
        self.people = PersonRepository()

    def test_returns_the_owners_people_keyed_by_id(self):
        ada = self.people.create("owner-a", PERSON_DATA)
        grace = self.people.create("owner-a", {**PERSON_DATA, "first_name": "Grace"})

        found = self.people.get_many_for_owner([grace.id, ada.id], "owner-a")

        self.assertEqual(set(found), {ada.id, grace.id})
        self.assertEqual(found[grace.id].first_name, "Grace")
        self.assertEqual(found[ada.id].lat, 51.5074)

    def test_leaves_out_other_owners_unknown_and_malformed_ids(self):
        mine = self.people.create("owner-a", PERSON_DATA)
        theirs = self.people.create("owner-b", PERSON_DATA)

        found = self.people.get_many_for_owner(
            [mine.id, theirs.id, "missing", "a/b", "__x__", ""], "owner-a"
        )

        self.assertEqual(set(found), {mine.id})

    def test_repeated_ids_are_read_once(self):
        mine = self.people.create("owner-a", PERSON_DATA)
        self.assertEqual(
            set(self.people.get_many_for_owner([mine.id, mine.id], "owner-a")),
            {mine.id},
        )

    def test_no_ids_means_no_read(self):
        self.assertEqual(self.people.get_many_for_owner([], "owner-a"), {})


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


class LastContactTests(FirestoreTestMixin, SimpleTestCase):
    """A person's last contact is stored on the person, so listing people is
    one query. Every log write has to keep it equal to their most recent
    log, which is what these check, against the logs as they really are."""

    collections_to_purge = ["people"]

    def setUp(self):
        super().setUp()
        self.people = PersonRepository()
        self.logs = ContactLogRepository()
        self.person = self.people.create("owner-a", PERSON_DATA)

    def log(self, day, channel="CALL"):
        return self.logs.create(
            "owner-a",
            self.person.id,
            {"channel": channel, "contacted_at": f"2026-07-{day:02d}T12:00:00+00:00"},
        )

    def last_contact(self):
        person = self.people.get_for_owner(self.person.id, "owner-a")
        return person.last_contacted_at, person.last_contact_channel

    def assert_last_contact(self, day, channel):
        self.assertEqual(
            self.last_contact(), (f"2026-07-{day:02d}T12:00:00+00:00", channel)
        )

    def stored_fields(self):
        return fs.collection("people").document(self.person.id).get().to_dict()

    def test_none_until_the_first_log(self):
        self.assertEqual(self.last_contact(), (None, None))
        self.assertNotIn("last_contacted_at", self.stored_fields())

    def test_an_older_log_written_later_does_not_replace_it(self):
        self.log(9, "VIDEO")
        self.log(3, "CALL")
        self.assert_last_contact(9, "VIDEO")

    def test_moving_the_latest_log_earlier_hands_it_to_the_next(self):
        self.log(5, "CALL")
        latest = self.log(9, "VIDEO")
        self.logs.update(
            latest.id, "owner-a", {"contacted_at": "2026-07-01T12:00:00+00:00"}
        )
        self.assert_last_contact(5, "CALL")

    def test_moving_an_older_log_later_makes_it_the_latest(self):
        older = self.log(2, "MESSAGE")
        self.log(5, "CALL")
        self.logs.update(
            older.id, "owner-a", {"contacted_at": "2026-07-20T12:00:00+00:00"}
        )
        self.assert_last_contact(20, "MESSAGE")

    def test_changing_the_latest_logs_channel(self):
        latest = self.log(5, "CALL")
        self.logs.update(latest.id, "owner-a", {"channel": "VIDEO"})
        self.assert_last_contact(5, "VIDEO")

    def test_a_note_edit_leaves_it(self):
        self.log(5, "CALL")
        older = self.log(2, "VIDEO")
        self.logs.update(older.id, "owner-a", {"note": "Rang back"})
        self.assert_last_contact(5, "CALL")

    def test_deleting_an_older_log_leaves_it(self):
        older = self.log(2, "VIDEO")
        self.log(5, "CALL")
        self.logs.delete(older.id, "owner-a")
        self.assert_last_contact(5, "CALL")

    def test_deleting_the_only_log_clears_it(self):
        only = self.log(5, "CALL")
        self.logs.delete(only.id, "owner-a")
        self.assertEqual(self.last_contact(), (None, None))
        self.assertNotIn("last_contacted_at", self.stored_fields())
        self.assertNotIn("last_contact_channel", self.stored_fields())

    def test_logs_written_at_once_leave_the_most_recent(self):
        """Each write reads the person and writes it back. Without a
        transaction, a write of an older log that read the person before a
        newer one landed would put the older one back."""
        days = [3, 17, 8, 25, 11, 21, 6, 14]
        start = threading.Barrier(len(days))

        def write(day):
            start.wait()
            self.log(day, f"CALL-{day}")

        threads = [threading.Thread(target=write, args=(day,)) for day in days]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertEqual(len(self.logs.list_for_owner("owner-a")), len(days))
        self.assert_last_contact(25, "CALL-25")

    def test_a_channel_edit_racing_a_date_edit_keeps_the_new_date(self):
        """Two PATCHes of one log: the channel-only one found the log before
        the other moved it to the 20th, and commits after it."""
        log = self.log(5, "CALL")
        found_before = self.logs._find(log.id, "owner-a")
        self.logs.update(
            log.id, "owner-a", {"contacted_at": "2026-07-20T12:00:00+00:00"}
        )

        with patch.object(self.logs, "_find", return_value=found_before):
            self.logs.update(log.id, "owner-a", {"channel": "VIDEO"})

        self.assert_last_contact(20, "VIDEO")

    def test_a_date_edit_racing_a_channel_edit_keeps_the_new_channel(self):
        # The log isn't among the two most recent until this edit moves it.
        log = self.log(2, "CALL")
        self.log(5, "CALL")
        self.log(6, "CALL")
        found_before = self.logs._find(log.id, "owner-a")
        self.logs.update(log.id, "owner-a", {"channel": "VIDEO"})

        with patch.object(self.logs, "_find", return_value=found_before):
            self.logs.update(
                log.id, "owner-a", {"contacted_at": "2026-07-20T12:00:00+00:00"}
            )

        self.assert_last_contact(20, "VIDEO")

    def test_a_person_write_cannot_set_it(self):
        self.log(5, "CALL")
        self.people.update(
            self.person.id,
            "owner-a",
            {
                "first_name": "Ada",
                "last_contacted_at": "2030-01-01T00:00:00+00:00",
                "last_contact_channel": "VIDEO",
            },
        )
        self.assert_last_contact(5, "CALL")


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

    def test_a_log_written_during_the_delete_goes_with_the_person(self):
        """A log created after the delete listed the person's logs, but before
        it committed, used to outlive the person: still listed by the
        collection-group query, and a 404 on every edit."""
        people = PersonRepository()
        logs = ContactLogRepository()
        person = people.create("owner-a", PERSON_DATA)
        logs.create(
            "owner-a",
            person.id,
            {"channel": "CALL", "contacted_at": "2026-07-01T12:00:00+00:00"},
        )
        # Purging people can't reach a log whose person is gone, so one left
        # behind by a failure here would turn up in every later test.
        orphans = fs.collection("people").document(person.id).collection("contact_logs")
        self.addCleanup(lambda: fs.delete_all(d.reference for d in orphans.stream()))
        list_logs = CollectionReference.stream
        raced = []

        def stream_then_log(collection, *args, **kwargs):
            found = list(list_logs(collection, *args, **kwargs))
            if collection.id == "contact_logs" and not raced:
                raced.append(
                    logs.create(
                        "owner-a",
                        person.id,
                        {"channel": "VIDEO", "contacted_at": "2026-07-02T12:00:00Z"},
                    )
                )
            return iter(found)

        with patch.object(CollectionReference, "stream", stream_then_log):
            self.assertTrue(people.delete(person.id, "owner-a"))

        self.assertIsNotNone(raced[0])
        self.assertEqual(logs.list_for_owner("owner-a"), [])
        self.assertIsNone(people.get_for_owner(person.id, "owner-a"))

    def test_a_person_that_keeps_changing_is_contention_not_a_crash(self):
        people = PersonRepository()
        person = people.create("owner-a", PERSON_DATA)

        with (
            patch.object(
                PersonRepository,
                "_delete_with_logs",
                side_effect=FailedPrecondition("changed"),
            ) as delete,
            self.assertRaises(fs.TransactionContention),
        ):
            people.delete(person.id, "owner-a")

        self.assertEqual(delete.call_count, DELETE_ATTEMPTS)
        self.assertIsNotNone(people.get_for_owner(person.id, "owner-a"))


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
