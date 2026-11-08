import os
from unittest import mock
from unittest.mock import patch

import firebase_admin
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.test import SimpleTestCase, override_settings
from google.api_core import exceptions

from apps.common import firestore as fs
from apps.common.testing import FirestoreTestMixin


class FirestoreClientTests(FirestoreTestMixin, SimpleTestCase):
    collections_to_purge = ["_smoke"]

    def test_client_is_singleton(self):
        self.assertIs(fs.get_client(), fs.get_client())

    def test_round_trip_document(self):
        ref = fs.collection("_smoke").document("doc1")
        ref.set({"value": 42})
        self.assertEqual(ref.get().to_dict()["value"], 42)

    def test_purge_between_tests_leaves_collection_empty(self):
        # The mixin purges in setUp, so the document written by the previous
        # test must not be visible here.
        self.assertEqual(len(list(fs.collection("_smoke").stream())), 0)

    def test_collection_shorthand_targets_named_collection(self):
        self.assertEqual(fs.collection("_smoke").id, "_smoke")


class FirestoreClientInitialisationTests(SimpleTestCase):
    """Exercises first-use initialisation by resetting the cached client."""

    def setUp(self):
        # get_client caches a process-wide client. Restore the real one so the
        # rest of the suite keeps sharing it.
        self.addCleanup(setattr, fs, "_client", fs._client)
        fs._client = None

    def _without_emulator_host(self):
        patcher = mock.patch.dict(os.environ)
        patcher.start()
        self.addCleanup(patcher.stop)
        os.environ.pop("FIRESTORE_EMULATOR_HOST", None)

    def test_initialises_client_for_configured_project(self):
        client = fs.get_client()
        self.assertEqual(client.project, settings.FIRESTORE_PROJECT_ID)
        self.assertIs(fs.get_client(), client)

    @override_settings(DEBUG=True)
    def test_debug_without_emulator_host_is_refused(self):
        # Without the emulator host, the client would silently target real
        # Firestore from a developer machine.
        self._without_emulator_host()
        with self.assertRaisesMessage(ImproperlyConfigured, "FIRESTORE_EMULATOR_HOST"):
            fs.get_client()
        # A refused configuration must not leave a half-built client cached.
        self.assertIsNone(fs._client)

    @override_settings(DEBUG=False)
    def test_production_without_emulator_host_is_allowed(self):
        # Production talks to real Firestore, so the check must not fire.
        self._without_emulator_host()
        fs._check_configuration()

    @override_settings(DEBUG=True)
    def test_debug_with_emulator_host_is_allowed(self):
        with mock.patch.dict(os.environ, {"FIRESTORE_EMULATOR_HOST": "firestore:8080"}):
            fs._check_configuration()

    def test_initialises_firebase_admin_app_once(self):
        with mock.patch.dict(firebase_admin._apps, clear=True):
            fs.get_client()
            app = firebase_admin.get_app()
            self.assertEqual(
                app.options.get("projectId"), settings.FIRESTORE_PROJECT_ID
            )

            # A second initialisation must reuse the existing default app;
            # initialize_app raises ValueError if called for it twice.
            fs._client = None
            fs.get_client()
            self.assertIs(firebase_admin.get_app(), app)

    def test_client_built_while_waiting_for_lock_is_reused(self):
        winner = fs.get_client()
        fs._client = None

        class _LockLostRace:
            """Simulates another thread finishing initialisation first."""

            def __enter__(self):
                fs._client = winner

            def __exit__(self, *exc_info):
                return False

        with mock.patch.object(fs, "_lock", _LockLostRace()):
            self.assertIs(fs.get_client(), winner)


class RunTransactionTests(FirestoreTestMixin, SimpleTestCase):
    """run_transaction retries contention in rounds with a random wait
    between them, and nothing else."""

    collections_to_purge = ["run_transaction_tests"]

    def setUp(self):
        super().setUp()
        sleep = patch("apps.common.firestore.time.sleep")
        self.sleep = sleep.start()
        self.addCleanup(sleep.stop)

    def rounds(self):
        """Run the transaction function once per round, without the client's
        own transaction wrapper, so a test decides how each round ends."""
        return patch("apps.common.firestore.gcloud_transactional", lambda f: f)

    @staticmethod
    def contention():
        # What the client raises when every attempt in a round aborted.
        error = ValueError("Failed to commit transaction in 3 attempts.")
        error.__cause__ = exceptions.Aborted("contention")
        return error

    def test_commits_and_returns_the_result(self):
        ref = fs.collection("run_transaction_tests").document("doc")

        def write(transaction):
            transaction.set(ref, {"written": True})
            return "done"

        self.assertEqual(fs.run_transaction(write), "done")
        self.assertTrue(ref.get().to_dict()["written"])
        self.sleep.assert_not_called()

    def test_waits_a_growing_random_time_after_each_round_lost(self):
        calls = []

        def lose_three_rounds(_transaction):
            calls.append(1)
            if len(calls) <= 3:
                raise self.contention()
            return "done"

        with self.rounds():
            self.assertEqual(fs.run_transaction(lose_three_rounds), "done")
        waits = [c.args[0] for c in self.sleep.call_args_list]
        self.assertEqual(len(waits), 3)
        for round_, wait in enumerate(waits):
            self.assertLessEqual(wait, fs.BACKOFF_BASE_S * 2**round_)

    def test_gives_up_after_the_last_round(self):
        def always_lose(_transaction):
            raise self.contention()

        with self.rounds(), self.assertRaises(ValueError):
            fs.run_transaction(always_lose)
        self.assertEqual(self.sleep.call_count, fs.TRANSACTION_ROUNDS - 1)

    def test_other_errors_are_not_retried(self):
        def broken(_transaction):
            raise ValueError("a bug in the transaction's own code")

        with self.rounds(), self.assertRaisesRegex(ValueError, "own code"):
            fs.run_transaction(broken)
        self.sleep.assert_not_called()


class DocumentIdTests(SimpleTestCase):
    def test_ids_firestore_can_address(self):
        for doc_id in ("abc", "Pp5ltxR4W9tpvZTZUlY7", "a.b", "é", "x" * 1500):
            with self.subTest(doc_id=doc_id[:20]):
                self.assertTrue(fs.is_valid_doc_id(doc_id))

    def test_ids_firestore_rejects(self):
        for doc_id in ("", "x/y", ".", "..", "__x__", None, 7):
            with self.subTest(doc_id=doc_id):
                self.assertFalse(fs.is_valid_doc_id(doc_id))

    # Firestore caps an id at 1,500 bytes. A longer one used to reach the
    # client, which sends it in a request header: the emulator dropped the
    # connection over the header's size and the client retried for five
    # minutes before a 500. Found by the nightly API fuzz test.
    def test_ids_over_1500_bytes_are_rejected(self):
        for doc_id in ("x" * 1501, "é" * 751, "🦄" * 376, "x" * 10_000):
            with self.subTest(length=len(doc_id)):
                self.assertFalse(fs.is_valid_doc_id(doc_id))

    def test_an_id_that_is_not_valid_unicode_is_rejected(self):
        self.assertFalse(fs.is_valid_doc_id("a\ud800b"))
