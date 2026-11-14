"""Firestore repository for user profiles.

The document ID is the owner key, so scoping is inherent — there is no query
to forget an ownership filter on.

    user_profiles/{ownerKey}
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, fields

from apps.common import firestore as fs

USER_PROFILES = "user_profiles"


@dataclass
class UserProfileRecord:
    owner_key: str
    profile_image: str | None = None
    city: str = ""
    state: str = ""
    country: str = ""
    street: str = ""
    birth_date: str | None = None
    phone_number: str = ""
    pin_color: str = "#2196F3"
    pin_style: str = "teardrop"
    pin_icon_type: str = "none"
    pin_emoji: str | None = None
    distance_unit: str = "metric"


_EDITABLE = {f.name for f in fields(UserProfileRecord)} - {"owner_key"}


class UnstorableOwnerKey(ValueError):
    """The owner key can't name a Firestore document.

    The key is the username, and Django's username validator allows ".",
    ".." and "__x__", which Firestore refuses as document ids. Sign-up and
    the Auth0 backend refuse such names, but an older account, an admin or a
    shell can still hold one, and its profile can't be read or written.
    """


class UserProfileRepository:
    def _document(self, owner_key: str):
        if not fs.is_valid_doc_id(owner_key):
            raise UnstorableOwnerKey(owner_key)
        return fs.collection(USER_PROFILES).document(owner_key)

    def _hydrate(self, owner_key: str, data: dict) -> UserProfileRecord:
        return UserProfileRecord(
            owner_key=owner_key,
            **{k: v for k, v in data.items() if k in _EDITABLE},
        )

    def get_or_create(self, owner_key: str) -> UserProfileRecord:
        ref = self._document(owner_key)
        doc = ref.get()
        if doc.exists:
            return self._hydrate(owner_key, doc.to_dict() or {})

        record = UserProfileRecord(owner_key=owner_key)
        payload = asdict(record)
        payload.pop("owner_key")
        ref.set(payload)
        return record

    def update(
        self,
        owner_key: str,
        data: dict,
        current: UserProfileRecord | None = None,
    ) -> UserProfileRecord:
        """Apply data to the profile, and return it as it is afterwards.

        current is the profile as get_or_create returned it, which saves
        reading (or creating) it again.
        """
        if current is None:
            self.get_or_create(owner_key)
        elif current.owner_key != owner_key:
            raise ValueError("current is not this owner's profile")
        payload = {k: v for k, v in data.items() if k in _EDITABLE}
        ref = self._document(owner_key)
        # Firestore raises "Cannot update with an empty document" rather than
        # no-opping, and a PATCH carrying only non-profile fields filters to {}.
        if payload:
            ref.update(payload)
        return self._hydrate(owner_key, ref.get().to_dict() or {})
