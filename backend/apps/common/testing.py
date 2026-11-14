"""Test support for emulator-backed tests.

Tests run against the real Firestore emulator rather than mocks, so state must
be purged between them. Mocking would only verify assumptions about Firestore
rather than Firestore itself.
"""

from __future__ import annotations

import collections
import contextlib
import functools
from unittest.mock import patch

from django.core.cache import cache
from google.cloud.firestore_v1.services.firestore.client import FirestoreClient

from apps.common import firestore as fs

# Every RPC the Firestore client can send. All of them go through the
# generated FirestoreClient, whatever the higher-level call (document get,
# query stream, batch commit, transaction), so counting calls here counts
# round trips to Firestore.
FIRESTORE_RPCS = (
    "batch_get_documents",
    "batch_write",
    "begin_transaction",
    "commit",
    "create_document",
    "delete_document",
    "get_document",
    "list_collection_ids",
    "list_documents",
    "listen",
    "partition_query",
    "rollback",
    "run_aggregation_query",
    "run_query",
    "update_document",
    "write",
)


class RpcCounts(collections.Counter):
    """Round trips by RPC name, plus the structured query of every run_query
    (google.cloud.firestore_v1.types.StructuredQuery), in order."""

    def __init__(self):
        super().__init__()
        self.queries: list = []


@contextlib.contextmanager
def count_firestore_rpcs():
    """Count the Firestore round trips made inside the block, by RPC name.

    Yields an RpcCounts that fills in as calls are made; sum(counts.values())
    is the number of round trips. A streamed query counts once, however many
    documents it returns.
    """
    counts = RpcCounts()

    def counting(name, original):
        @functools.wraps(original)
        def wrapper(self, *args, **kwargs):
            counts[name] += 1
            if name == "run_query":
                request = kwargs.get("request") or args[0]
                counts.queries.append(request["structured_query"])
            return original(self, *args, **kwargs)

        return wrapper

    with contextlib.ExitStack() as stack:
        for name in FIRESTORE_RPCS:
            original = getattr(FirestoreClient, name)
            stack.enter_context(
                patch.object(FirestoreClient, name, counting(name, original))
            )
        yield counts


def _delete_document(reference, batch_size: int) -> None:
    """Delete a document reference after recursively purging its subcollections."""
    for sub in reference.collections():
        for child in _documents(sub, batch_size):
            _delete_document(child, batch_size)
    reference.delete()


def _documents(collection, batch_size: int) -> list:
    """Every document in a collection, including missing ones: a document
    that was deleted, or never written, but still has subcollection
    documents under it. Firestore keeps those when their parent goes, and
    a collection-group query (a trip's legs, a person's contact logs) still
    finds them, so a test that failed part-way through a delete would
    otherwise leave them for later tests to see. list_documents asks for
    missing documents too (show_missing), where a query would skip them."""
    return list(collection.list_documents(page_size=batch_size))


def purge_collection(name: str, batch_size: int = 200) -> None:
    """Recursively delete every document in a collection, including
    subcollections and documents left under a missing parent."""
    for doc in _documents(fs.collection(name), batch_size):
        _delete_document(doc, batch_size)


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
