"""Firestore repositories for Person and ContactLog.

Every read method takes an owner_key and there is no unscoped alternative.
Ownership isolation is therefore structural rather than a filter a caller can
forget — the property the security suite in tests/test_api_security.py asserts.

Layout:
    people/{personId}                 owner_key: str | None  (None = public)
      └── contact_logs/{logId}
"""

from __future__ import annotations

import re
from dataclasses import dataclass, fields
from datetime import UTC, datetime

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
_PERSON_WRITABLE_FIELDS = _PERSON_FIELDS - {"owner_key"}


def _now_iso() -> str:
    return datetime.now(UTC).isoformat()


def _is_valid_id(doc_id: str) -> bool:
    """Whether doc_id can name a document directly in a collection.

    Ids reach the repositories from request bodies and query strings. Firestore
    rejects an empty id, "." / "..", and reserved __names__ outright (a 500 if
    it reached the client), and a "/" would address a different, deeper path.
    Such ids can never name a real record, so they are treated as not found.
    """
    return (
        bool(doc_id)
        and "/" not in doc_id
        and doc_id not in {".", ".."}
        and re.fullmatch(r"__.*__", doc_id) is None
    )


class PersonRepository:
    def _collection(self):
        return fs.collection(PEOPLE)

    def _hydrate(self, doc) -> PersonRecord:
        data = doc.to_dict() or {}
        record = PersonRecord(
            id=doc.id,
            **{k: v for k, v in data.items() if k in _PERSON_FIELDS},
        )
        latest = self._latest_log(doc.reference)
        if latest is not None:
            record.last_contacted_at = latest.get("contacted_at")
            record.last_contact_channel = latest.get("channel")
        return record

    def _latest_log(self, person_ref) -> dict | None:
        docs = list(
            person_ref.collection(CONTACT_LOGS)
            .order_by("contacted_at", direction="DESCENDING")
            .limit(1)
            .stream()
        )
        return docs[0].to_dict() if docs else None

    def list_for_owner(self, owner_key: str | None) -> list[PersonRecord]:
        query = self._collection().where("owner_key", "==", owner_key)
        return [self._hydrate(doc) for doc in query.stream()]

    def get_for_owner(
        self, person_id: str, owner_key: str | None
    ) -> PersonRecord | None:
        if not _is_valid_id(person_id):
            return None
        doc = self._collection().document(person_id).get()
        if not doc.exists:
            return None
        if (doc.to_dict() or {}).get("owner_key") != owner_key:
            return None
        return self._hydrate(doc)

    def create(self, owner_key: str | None, data: dict) -> PersonRecord:
        payload = {k: v for k, v in data.items() if k in _PERSON_WRITABLE_FIELDS}
        payload["owner_key"] = owner_key
        payload["created_at"] = _now_iso()
        payload["updated_at"] = _now_iso()

        ref = self._collection().document()
        ref.set(payload)
        return self._hydrate(ref.get())

    def update(
        self, person_id: str, owner_key: str | None, data: dict
    ) -> PersonRecord | None:
        if not _is_valid_id(person_id):
            return None
        ref = self._collection().document(person_id)
        doc = ref.get()
        if not doc.exists or (doc.to_dict() or {}).get("owner_key") != owner_key:
            return None

        payload = {k: v for k, v in data.items() if k in _PERSON_WRITABLE_FIELDS}
        payload["updated_at"] = _now_iso()
        ref.update(payload)
        return self._hydrate(ref.get())

    def delete(self, person_id: str, owner_key: str | None) -> bool:
        if not _is_valid_id(person_id):
            return False
        ref = self._collection().document(person_id)
        doc = ref.get()
        if not doc.exists or (doc.to_dict() or {}).get("owner_key") != owner_key:
            return False

        for log in ref.collection(CONTACT_LOGS).stream():
            log.reference.delete()
        ref.delete()
        return True


class ContactLogRepository:
    def __init__(self):
        self._people = PersonRepository()

    def _person_ref_if_owned(self, person_id: str, owner_key: str | None):
        if not _is_valid_id(person_id):
            return None
        ref = fs.collection(PEOPLE).document(person_id)
        doc = ref.get()
        if not doc.exists or (doc.to_dict() or {}).get("owner_key") != owner_key:
            return None
        return ref

    def _hydrate(self, doc, person_id: str) -> ContactLogRecord:
        data = doc.to_dict() or {}
        return ContactLogRecord(
            id=doc.id,
            person_id=person_id,
            channel=data.get("channel", ""),
            contacted_at=data.get("contacted_at", ""),
            note=data.get("note"),
            created_at=data.get("created_at"),
        )

    def list_for_owner(
        self, owner_key: str | None, person_id: str | None = None
    ) -> list[ContactLogRecord]:
        if person_id is not None:
            ref = self._person_ref_if_owned(person_id, owner_key)
            if ref is None:
                return []
            person_refs = [ref]
        else:
            person_refs = [
                fs.collection(PEOPLE).document(p.id)
                for p in self._people.list_for_owner(owner_key)
            ]

        records: list[ContactLogRecord] = []
        for ref in person_refs:
            for doc in (
                ref.collection(CONTACT_LOGS)
                .order_by("contacted_at", direction="DESCENDING")
                .stream()
            ):
                records.append(self._hydrate(doc, ref.id))

        records.sort(key=lambda r: r.contacted_at, reverse=True)
        return records

    def get_for_owner(
        self, log_id: str, owner_key: str | None
    ) -> ContactLogRecord | None:
        for record in self.list_for_owner(owner_key):
            if record.id == log_id:
                return record
        return None

    def create(
        self, owner_key: str | None, person_id: str, data: dict
    ) -> ContactLogRecord | None:
        person_ref = self._person_ref_if_owned(person_id, owner_key)
        if person_ref is None:
            return None

        payload = {
            "channel": data["channel"],
            "contacted_at": data["contacted_at"],
            "note": data.get("note"),
            "created_at": _now_iso(),
        }
        ref = person_ref.collection(CONTACT_LOGS).document()
        ref.set(payload)
        return self._hydrate(ref.get(), person_id)

    def update(
        self, log_id: str, owner_key: str | None, data: dict
    ) -> ContactLogRecord | None:
        existing = self.get_for_owner(log_id, owner_key)
        if existing is None:
            return None

        ref = (
            fs.collection(PEOPLE)
            .document(existing.person_id)
            .collection(CONTACT_LOGS)
            .document(log_id)
        )
        payload = {
            k: v for k, v in data.items() if k in {"channel", "contacted_at", "note"}
        }
        # Firestore raises "Cannot update with an empty document" rather than
        # no-opping, and a PATCH with none of these fields filters to {}.
        if payload:
            ref.update(payload)
        return self._hydrate(ref.get(), existing.person_id)

    def delete(self, log_id: str, owner_key: str | None) -> bool:
        existing = self.get_for_owner(log_id, owner_key)
        if existing is None:
            return False

        fs.collection(PEOPLE).document(existing.person_id).collection(
            CONTACT_LOGS
        ).document(log_id).delete()
        return True
