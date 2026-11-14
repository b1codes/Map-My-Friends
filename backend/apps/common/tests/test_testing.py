from django.test import SimpleTestCase

from apps.common import firestore as fs
from apps.common.testing import purge_collection


class PurgeCollectionTests(SimpleTestCase):
    """Tests share the emulator, so a purge must leave nothing behind."""

    def test_purges_documents_whose_parent_is_gone(self):
        """A subcollection document outlives a deleted parent (a test that
        failed mid-delete leaves one), and lists by collection group, such
        as a trip's legs or a person's contact logs, would still see it."""
        refs = [
            fs.collection("trips").document("purge-real"),
            fs.collection("trips")
            .document("purge-real")
            .collection("legs")
            .document("leg"),
            fs.collection("trips")
            .document("purge-gone")
            .collection("stops")
            .document("stop"),
            fs.collection("trips")
            .document("purge-gone")
            .collection("legs")
            .document("leg"),
            fs.collection("people")
            .document("purge-gone")
            .collection("contact_logs")
            .document("log"),
        ]
        for ref in refs:
            ref.set({"owner_key": "purge-test"})

        purge_collection("trips")
        purge_collection("people")

        for ref in refs:
            with self.subTest(path=ref.path):
                self.assertFalse(ref.get().exists)
