import os
from io import StringIO
from unittest import mock

from django.contrib.auth.models import User
from django.core.management import CommandError, call_command
from django.test import TestCase

from apps.common import firestore as fs
from apps.common.management.commands import seed
from apps.common.testing import FirestoreTestMixin


class SeedCommandTests(FirestoreTestMixin, TestCase):
    collections_to_purge = ["people", "trips", "user_profiles"]

    def _seed(self):
        out = StringIO()
        call_command("seed", stdout=out)
        return out.getvalue()

    def _people_docs(self):
        return list(fs.collection("people").where("owner_key", "==", "demo").stream())

    def test_creates_demo_user_with_documented_password(self):
        # README's DEV Sign In button logs in with these credentials.
        output = self._seed()
        user = User.objects.get(username=seed.DEMO_USERNAME)
        self.assertTrue(user.check_password(seed.DEMO_PASSWORD))
        self.assertEqual(user.email, "demo@example.com")
        self.assertIn("Created Django user 'demo'", output)

    def test_existing_demo_user_is_reused_and_password_untouched(self):
        User.objects.create_user(username="demo", password="changed-locally-1!")
        output = self._seed()
        self.assertEqual(User.objects.filter(username="demo").count(), 1)
        self.assertTrue(
            User.objects.get(username="demo").check_password("changed-locally-1!")
        )
        self.assertNotIn("Created Django user", output)

    def test_creates_profile_keyed_by_username(self):
        self._seed()
        self.assertTrue(fs.collection("user_profiles").document("demo").get().exists)

    def test_creates_sample_people_owned_by_demo(self):
        output = self._seed()
        people = {
            doc.to_dict()["first_name"]: doc.to_dict() for doc in self._people_docs()
        }
        self.assertEqual(set(people), {"Ada", "Grace", "Alan"})
        self.assertEqual(people["Grace"]["tag"], "FAMILY")
        self.assertEqual(people["Alan"]["lat"], 41.8781)
        self.assertEqual(people["Alan"]["lng"], -87.6298)
        self.assertEqual(people["Ada"]["timezone"], "Europe/London")
        self.assertEqual(people["Grace"]["contact_cadence_days"], 14)
        self.assertIn("  person: Ada Lovelace", output)
        # Nothing should leak into the public (owner_key=None) dataset.
        self.assertEqual(
            len(list(fs.collection("people").where("owner_key", "==", None).stream())),
            0,
        )

    def test_logs_contact_history_for_first_two_people(self):
        self._seed()
        logs = {}
        for doc in self._people_docs():
            entries = [
                log.to_dict()
                for log in doc.reference.collection("contact_logs").stream()
            ]
            logs[doc.to_dict()["first_name"]] = entries

        self.assertEqual(len(logs["Ada"]), 1)
        self.assertEqual(logs["Ada"][0]["channel"], "CALL")
        self.assertEqual(logs["Ada"][0]["note"], "Caught up")
        self.assertEqual(logs["Grace"][0]["channel"], "VIDEO")
        self.assertIsNone(logs["Grace"][0]["note"])
        self.assertEqual(logs["Alan"], [])

    def test_creates_draft_trip(self):
        output = self._seed()
        trips = [
            doc.to_dict()
            for doc in fs.collection("trips").where("owner_key", "==", "demo").stream()
        ]
        self.assertEqual(len(trips), 1)
        self.assertEqual(trips[0]["name"], "Summer visit")
        self.assertEqual(trips[0]["status"], "DRAFT")
        self.assertEqual(trips[0]["start_date"], "2026-08-01")
        self.assertEqual(trips[0]["end_date"], "2026-08-10")
        self.assertIn("  trip: Summer visit", output)
        self.assertIn("Seed complete.", output)

    def test_refuses_to_run_without_emulator(self):
        with mock.patch.dict(os.environ):
            os.environ.pop("FIRESTORE_EMULATOR_HOST", None)
            with self.assertRaisesMessage(CommandError, "Refusing to seed"):
                self._seed()
        self.assertFalse(User.objects.filter(username="demo").exists())
        self.assertEqual(self._people_docs(), [])
