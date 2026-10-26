import os
from unittest import mock

import firebase_admin
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.test import SimpleTestCase, override_settings

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
