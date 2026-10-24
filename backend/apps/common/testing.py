"""Test support for emulator-backed tests.

Tests run against the real Firestore emulator rather than mocks, so state must
be purged between them. Mocking would only verify assumptions about Firestore
rather than Firestore itself.
"""

from __future__ import annotations

from django.core.cache import cache

from apps.common import firestore as fs


def _delete_document(reference, batch_size: int) -> None:
    """Delete a document reference after recursively purging its subcollections."""
    for sub in reference.collections():
        while True:
            sub_docs = list(sub.limit(batch_size).stream())
            if not sub_docs:
                break
            for sub_doc in sub_docs:
                _delete_document(sub_doc.reference, batch_size)
    reference.delete()


def purge_collection(name: str, batch_size: int = 200) -> None:
    """Recursively delete every document in a collection, including subcollections."""
    collection = fs.collection(name)
    while True:
        docs = list(collection.limit(batch_size).stream())
        if not docs:
            return
        for doc in docs:
            _delete_document(doc.reference, batch_size)


class FirestoreTestMixin:
    """Purges the named collections before each test.

    Usage:
        class MyTests(FirestoreTestMixin, APITestCase):
            collections_to_purge = ["people", "trips"]
    """

    collections_to_purge: list[str] = ["people", "trips", "user_profiles"]

    def setUp(self):
        for name in self.collections_to_purge:
            purge_collection(name)
        super().setUp()


class ThrottleIsolationMixin:
    """Clears throttle history around each test.

    DRF keeps throttle counters in the process-wide cache, and the anonymous
    buckets are small (anon_burst is 10/minute), so without this the outcome of
    a test would depend on how many requests earlier tests, in any app,
    happened to make.
    """

    def setUp(self):
        cache.clear()
        self.addCleanup(cache.clear)
        super().setUp()
