"""Firestore client singleton.

google.cloud.firestore.Client detects FIRESTORE_EMULATOR_HOST itself and
routes to the emulator when it is set, so no application code branches on
environment. That is what makes local behaviour a faithful predictor of
production.
"""

from __future__ import annotations

import os
import re
import threading

import firebase_admin
from django.core.exceptions import ImproperlyConfigured
from google.cloud import firestore

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
    Firestore rejects an empty id, "." / "..", and reserved __names__ outright
    (a 500 if it reached the client), and a "/" would address a different,
    deeper path. Such ids can never name a real record, so callers treat them
    as not found.
    """
    return (
        isinstance(doc_id, str)
        and bool(doc_id)
        and "/" not in doc_id
        and doc_id not in {".", ".."}
        and re.fullmatch(r"__.*__", doc_id) is None
    )


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
