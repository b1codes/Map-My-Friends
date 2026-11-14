"""Firestore repositories for Person and ContactLog.

Every read method takes an owner_key and there is no unscoped alternative.
Ownership isolation is therefore structural rather than a filter a caller can
forget — the property the security suite in tests/test_api_security.py asserts.

Layout:
    people/{personId}       owner_key: str | None  (None = public)
      │                     last_contacted_at, last_contact_channel: the
      │                     person's most recent log, kept in step with the
      │                     logs, absent while there are none
      └── contact_logs/{logId}
                            owner_key, log_id: copies of the person's owner and
                            the document's own id, so a collection-group query
                            finds an owner's logs, or one log, in one round trip

Every request costs a fixed number of round trips, whatever the size of the
account; tests/test_round_trip_budgets.py holds each route to its count.
"""

from __future__ import annotations

from dataclasses import dataclass, fields, replace
from datetime import UTC, datetime

from google.api_core.exceptions import NotFound
from google.cloud.firestore_v1 import DELETE_FIELD
from google.cloud.firestore_v1.base_query import FieldFilter

from apps.common import firestore as fs

PEOPLE = "people"
CONTACT_LOGS = "contact_logs"


@dataclass
class PersonRecord:
    id: str
    owner_key: str | None = None
    tag: str = ""
    first_name: str = ""
    last_name: str = ""
    city: str = ""
    state: str = ""
    country: str = ""
    street: str | None = None
    birthday: str | None = None
    phone_number: str | None = None
    profile_image: str | None = None
    lat: float | None = None
    lng: float | None = None
    timezone: str | None = None
    pin_color: str = "#F44336"
    pin_style: str = "teardrop"
    pin_icon_type: str = "none"
    pin_emoji: str | None = None
    contact_cadence_days: int | None = None
    preferred_airport: int | None = None
    preferred_station: int | None = None
    last_contacted_at: str | None = None
    last_contact_channel: str | None = None


@dataclass
class ContactLogRecord:
    id: str
    person_id: str
    channel: str
    contacted_at: str
    note: str | None = None
    created_at: str | None = None


_PERSON_FIELDS = {f.name for f in fields(PersonRecord)} - {"id"}

# owner_key is deliberately NOT writable from caller-supplied data. `create`
# sets it from its own argument and `update` must never change it, or a caller
# passing {"owner_key": "someone-else"} could hand their record to another
# owner (or claim one). The serializer also marks it read-only, but ownership
# is enforced here so the repository stays the security boundary on its own.
_PERSON_WRITABLE_FIELDS = (
    _PERSON_FIELDS
    - {"owner_key"}
    - {
        # Derived from the person's logs; only the log writes below set them.
        "last_contacted_at",
        "last_contact_channel",
    }
)


def _now_iso() -> str:
    return datetime.now(UTC).isoformat()


_is_valid_id = fs.is_valid_doc_id


class PersonRepository:
    def _collection(self):
        return fs.collection(PEOPLE)

    @staticmethod
    def _record(person_id: str, data: dict) -> PersonRecord:
        return PersonRecord(
            id=person_id, **{k: v for k, v in data.items() if k in _PERSON_FIELDS}
        )

    def _hydrate(self, doc) -> PersonRecord:
        return self._record(doc.id, doc.to_dict() or {})

    def _owned_doc(self, person_id: str, owner_key: str | None):
        """The person's snapshot if owner_key owns it, else None."""
        if not _is_valid_id(person_id):
            return None
        doc = self._collection().document(person_id).get()
        if not doc.exists or (doc.to_dict() or {}).get("owner_key") != owner_key:
            return None
        return doc

    def list_for_owner(self, owner_key: str | None) -> list[PersonRecord]:
        query = self._collection().where(
            filter=FieldFilter("owner_key", "==", owner_key)
        )
        return [self._hydrate(doc) for doc in query.stream()]

    def get_for_owner(
        self, person_id: str, owner_key: str | None
    ) -> PersonRecord | None:
        doc = self._owned_doc(person_id, owner_key)
        return self._hydrate(doc) if doc is not None else None

    def get_many_for_owner(
        self, person_ids, owner_key: str | None
    ) -> dict[str, PersonRecord]:
        """The owner's people among person_ids, keyed by id, in one read.

        Ids that are unknown, malformed or someone else's are left out.
        """
        refs = [
            self._collection().document(person_id)
            for person_id in dict.fromkeys(person_ids)
            if _is_valid_id(person_id)
        ]
        if not refs:
            return {}
        found = {}
        for doc in fs.get_client().get_all(refs):
            data = doc.to_dict() if doc.exists else None
            if data is None or data.get("owner_key") != owner_key:
                continue
            found[doc.id] = self._record(doc.id, data)
        return found

    def create(self, owner_key: str | None, data: dict) -> PersonRecord:
        payload = {k: v for k, v in data.items() if k in _PERSON_WRITABLE_FIELDS}
        payload["owner_key"] = owner_key
        payload["created_at"] = _now_iso()
        payload["updated_at"] = _now_iso()
        ref = self._collection().document()
        ref.set(payload)
        return self._record(ref.id, payload)

    def update(
        self,
        person_id: str,
        owner_key: str | None,
        data: dict,
        current: PersonRecord | None = None,
    ) -> PersonRecord | None:
        """Apply data to the person, and return them as they are afterwards.

        current is the person as get_for_owner returned them, to save reading
        them again. None when they aren't owner_key's, or were deleted before
        the write landed.
        """
        if current is None:
            current = self.get_for_owner(person_id, owner_key)
            if current is None:
                return None
        elif (current.id, current.owner_key) != (person_id, owner_key):
            raise ValueError("current is not this owner's person")

        payload = {k: v for k, v in data.items() if k in _PERSON_WRITABLE_FIELDS}
        payload["updated_at"] = _now_iso()
        try:
            self._collection().document(person_id).update(payload)
        except NotFound:
            return None
        return replace(
            current, **{k: v for k, v in payload.items() if k in _PERSON_FIELDS}
        )

    def delete(self, person_id: str, owner_key: str | None) -> PersonRecord | None:
        """Delete the person and their logs, and return the person as they
        were. None when they aren't owner_key's."""
        doc = self._owned_doc(person_id, owner_key)
        if doc is None:
            return None
        # Firestore leaves subcollections behind when a parent is deleted, so
        # the logs go in the same commit.
        logs = [
            log.reference for log in doc.reference.collection(CONTACT_LOGS).stream()
        ]
        fs.delete_all([*logs, doc.reference])
        return self._hydrate(doc)


def _last_contact(log: dict | None) -> dict:
    """The person fields that mirror their most recent log."""
    if log is None:
        return {"last_contacted_at": DELETE_FIELD, "last_contact_channel": DELETE_FIELD}
    return {
        "last_contacted_at": log["contacted_at"],
        "last_contact_channel": log["channel"],
    }


def _is_newer(log: dict, than: str | None) -> bool:
    return than is None or log["contacted_at"] >= than


class ContactLogRepository:
    def _owned_logs(self, owner_key: str | None):
        return (
            fs.get_client()
            .collection_group(CONTACT_LOGS)
            .where(filter=FieldFilter("owner_key", "==", owner_key))
        )

    def _find(self, log_id: str, owner_key: str | None):
        """The owner's log document with this id, or None."""
        if not _is_valid_id(log_id):
            return None
        query = self._owned_logs(owner_key).where(
            filter=FieldFilter("log_id", "==", log_id)
        )
        docs = list(query.limit(1).stream())
        return docs[0] if docs else None

    @staticmethod
    def _record(log_id: str, person_id: str, data: dict) -> ContactLogRecord:
        return ContactLogRecord(
            id=log_id,
            person_id=person_id,
            channel=data.get("channel", ""),
            contacted_at=data.get("contacted_at", ""),
            note=data.get("note"),
            created_at=data.get("created_at"),
        )

    def _hydrate(self, doc) -> ContactLogRecord:
        return self._record(doc.id, doc.reference.parent.parent.id, doc.to_dict() or {})

    def list_for_owner(
        self, owner_key: str | None, person_id: str | None = None
    ) -> list[ContactLogRecord]:
        if person_id is None:
            query = self._owned_logs(owner_key)
        elif not _is_valid_id(person_id):
            return []
        else:
            # The logs carry their person's owner, so this finds nothing
            # under someone else's person without reading the person.
            query = (
                fs.collection(PEOPLE)
                .document(person_id)
                .collection(CONTACT_LOGS)
                .where(filter=FieldFilter("owner_key", "==", owner_key))
            )
        records = [self._hydrate(doc) for doc in query.stream()]
        records.sort(key=lambda r: r.contacted_at, reverse=True)
        return records

    def get_for_owner(
        self, log_id: str, owner_key: str | None
    ) -> ContactLogRecord | None:
        doc = self._find(log_id, owner_key)
        return self._hydrate(doc) if doc is not None else None

    def create(
        self, owner_key: str | None, person_id: str, data: dict
    ) -> ContactLogRecord | None:
        if not _is_valid_id(person_id):
            return None
        person_ref = fs.collection(PEOPLE).document(person_id)
        ref = person_ref.collection(CONTACT_LOGS).document()
        payload = {
            "owner_key": owner_key,
            "log_id": ref.id,
            "channel": data["channel"],
            "contacted_at": data["contacted_at"],
            "note": data.get("note"),
            "created_at": _now_iso(),
        }

        # In a transaction, so two logs written at once can't leave the
        # person showing the older one as their last contact.
        def write(transaction) -> bool:
            person = person_ref.get(transaction=transaction)
            person_data = person.to_dict() if person.exists else None
            if person_data is None or person_data.get("owner_key") != owner_key:
                return False
            transaction.set(ref, payload)
            if _is_newer(payload, person_data.get("last_contacted_at")):
                transaction.update(person_ref, _last_contact(payload))
            return True

        if not fs.run_transaction(write):
            return None
        return self._record(ref.id, person_id, payload)

    def _write_and_refresh_last_contact(self, doc, change: dict | None) -> bool:
        """Apply change to the log doc (None deletes it), and set its person's
        last contact from the logs as they will be afterwards.

        False, writing nothing, when a change finds the log deleted since doc
        was read.
        """
        log_ref = doc.reference
        person_ref = log_ref.parent.parent
        latest_two = (
            person_ref.collection(CONTACT_LOGS)
            .order_by("contacted_at", direction="DESCENDING")
            .limit(2)
        )

        def write(transaction) -> bool:
            # The two most recent logs are enough: whether or not this log is
            # one of them, the other is the most recent of the rest.
            latest_logs = list(latest_two.stream(transaction=transaction))
            candidates = [d.to_dict() for d in latest_logs if d.id != log_ref.id][:1]
            if change is None:
                transaction.delete(log_ref)
            else:
                # The log as this transaction reads it, not as doc does: an
                # edit committed since doc was read would otherwise be undone
                # on the person.
                edited = next(
                    (d.to_dict() for d in latest_logs if d.id == log_ref.id), None
                )
                if edited is None and not {"channel", "contacted_at"} <= change.keys():
                    # Not among the two most recent, and the change keeps one
                    # of the fields the person mirrors from it.
                    edited = log_ref.get(transaction=transaction).to_dict()
                    if edited is None:
                        return False
                transaction.update(log_ref, change)
                candidates.append({**(edited or {}), **change})
            latest = max(candidates, key=lambda log: log["contacted_at"], default=None)
            transaction.update(person_ref, _last_contact(latest))
            return True

        return fs.run_transaction(write)

    def update(
        self, log_id: str, owner_key: str | None, data: dict
    ) -> ContactLogRecord | None:
        doc = self._find(log_id, owner_key)
        if doc is None:
            return None

        payload = {
            k: v for k, v in data.items() if k in {"channel", "contacted_at", "note"}
        }
        if {"channel", "contacted_at"} & payload.keys():
            if not self._write_and_refresh_last_contact(doc, payload):
                return None
        elif payload:
            # Firestore raises "Cannot update with an empty document" rather
            # than no-opping, and a PATCH with none of these fields filters to
            # {}.
            doc.reference.update(payload)
        return self._record(
            doc.id, doc.reference.parent.parent.id, {**(doc.to_dict() or {}), **payload}
        )

    def delete(self, log_id: str, owner_key: str | None) -> bool:
        doc = self._find(log_id, owner_key)
        if doc is None:
            return False
        self._write_and_refresh_last_contact(doc, None)
        return True
