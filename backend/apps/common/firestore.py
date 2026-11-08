"""Firestore client singleton.

google.cloud.firestore.Client detects FIRESTORE_EMULATOR_HOST itself and
routes to the emulator when it is set, so no application code branches on
environment. That is what makes local behaviour a faithful predictor of
production.
"""

from __future__ import annotations

import os
import random
import re
import threading
import time

import firebase_admin
from django.core.exceptions import ImproperlyConfigured
from google.api_core import exceptions
from google.cloud import firestore
from google.cloud.firestore_v1 import transactional as gcloud_transactional

_lock = threading.Lock()
_client = None


def _check_configuration() -> None:
    from django.conf import settings

    if settings.DEBUG and not os.environ.get("FIRESTORE_EMULATOR_HOST"):
        raise ImproperlyConfigured(
            "FIRESTORE_EMULATOR_HOST is not set while DEBUG=True. Start the "
            "emulator with `make up` (or `docker compose up firestore`), which "
            "sets FIRESTORE_EMULATOR_HOST=firestore:8080 for the api service."
        )


def get_client():
    """Return the process-wide Firestore client, initialising it on first use."""
    global _client
    if _client is None:
        with _lock:
            if _client is None:
                from django.conf import settings

                _check_configuration()
                if not firebase_admin._apps:
                    # Not consulted for Firestore itself (see the
                    # google.cloud.firestore.Client note below) — this App is
                    # kept initialised for a future Auth/GCIP task that will
                    # need firebase_admin.auth. Currently unused for the
                    # Firestore path, not dead code.
                    firebase_admin.initialize_app(
                        options={"projectId": settings.FIRESTORE_PROJECT_ID}
                    )
                # google.cloud.firestore.Client checks FIRESTORE_EMULATOR_HOST
                # itself and substitutes anonymous credentials when it is set
                # (see firestore_v1.base_client.BaseClient.__init__). Using it
                # directly, rather than firebase_admin.firestore.client(),
                # matters because that wrapper unconditionally resolves
                # Application Default Credentials before this check ever
                # happens, which fails outside a real GCP environment. This
                # is the single call path for both the emulator and
                # production Firestore.
                _client = firestore.Client(project=settings.FIRESTORE_PROJECT_ID)
    return _client


def collection(name: str):
    """Shorthand for get_client().collection(name)."""
    return get_client().collection(name)


def is_valid_doc_id(doc_id) -> bool:
    """Whether doc_id can name a document directly in a collection.

    Ids reach the repositories from URLs, request bodies and query strings.
    Firestore rejects an empty id, "." / "..", reserved __names__, and an id
    over 1,500 bytes of UTF-8 outright (a 500 if it reached the client; an
    over-long id went out in a request header and the client retried it for
    five minutes first), and a "/" would address a different, deeper path.
    Such ids can never name a real record, so callers treat them as not
    found.
    """
    if not isinstance(doc_id, str) or not doc_id:
        return False
    try:
        size = len(doc_id.encode("utf-8"))
    except UnicodeEncodeError:
        return False  # a lone surrogate: not UTF-8, so not storable
    return (
        size <= MAX_DOC_ID_BYTES
        and "/" not in doc_id
        and doc_id not in {".", ".."}
        and re.fullmatch(r"__.*__", doc_id) is None
    )


# Firestore's limit on a document id.
MAX_DOC_ID_BYTES = 1500


# Firestore's limit on the writes in one commit.
MAX_WRITES_PER_COMMIT = 500


def delete_all(refs) -> None:
    """Delete every document in refs, in as few commits as the limit allows."""
    refs = list(refs)
    for start in range(0, len(refs), MAX_WRITES_PER_COMMIT):
        batch = get_client().batch()
        for ref in refs[start : start + MAX_WRITES_PER_COMMIT]:
            batch.delete(ref)
        batch.commit()


# Transactions are retried in rounds: each round is a transaction with
# the client's own quick retries (a retried transaction keeps its place in
# line), and between rounds the caller waits a random, growing time. Without
# the waits, writers that abort one another retry in step and can keep doing
# so: on CI's emulator, eight log writes to one person at once had seven give
# up after ten immediate retries each, which the API answers with a 500.
TRANSACTION_ROUNDS = 6
ATTEMPTS_PER_ROUND = 3
BACKOFF_BASE_S = 0.05
BACKOFF_MAX_S = 1.0


def _gave_up_on_contention(exc: ValueError) -> bool:
    """Whether the client gave up retrying a transaction that kept aborting,
    as opposed to the transaction's own code raising ValueError."""
    return isinstance(exc.__cause__, exceptions.Aborted)


def run_transaction(fn):
    """Run fn(transaction) in a transaction and return its result, retrying
    on contention. fn may run more than once, so it must only read and write
    through the transaction it is given."""
    transactional_fn = gcloud_transactional(fn)
    for round_ in range(TRANSACTION_ROUNDS - 1):
        try:
            return transactional_fn(
                get_client().transaction(max_attempts=ATTEMPTS_PER_ROUND)
            )
        except ValueError as exc:
            if not _gave_up_on_contention(exc):
                raise
        time.sleep(random.uniform(0, min(BACKOFF_MAX_S, BACKOFF_BASE_S * 2**round_)))
    return transactional_fn(get_client().transaction(max_attempts=ATTEMPTS_PER_ROUND))
