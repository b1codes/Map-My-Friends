"""Provider states: the Django side of contracts/api/fixtures.json.

Each state builds its part of the shared world for real, in the Firestore
emulator and the test database, and returns the real value behind each
placeholder role, so a contract request written against illustrative ids can
be replayed as-is.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from django.contrib.auth.models import User
from rest_framework_simplejwt.serializers import (
    TokenObtainPairSerializer,
    TokenRefreshSerializer,
)
from rest_framework_simplejwt.tokens import RefreshToken

from apps.people.repositories import ContactLogRepository, PersonRepository
from apps.people.serializers import ContactLogSerializer, PersonSerializer
from apps.trips.repositories import TripRepository
from apps.trips.serializers import TripSerializer
from apps.users.serializers import (
    PasswordResetRequestSerializer,
    RegisterSerializer,
    UserProfileSerializer,
)

from .support import fixtures


@dataclass
class ProviderState:
    user: User | None = None
    # Placeholder role (see fixtures.json) -> the real value created for it.
    roles: dict[str, str] = field(default_factory=dict)


def anonymous() -> ProviderState:
    return ProviderState()


def registered_user() -> ProviderState:
    spec = fixtures()["user"]
    user = User.objects.create_user(
        username=spec["username"],
        password=spec["password"],
        email=spec["email"],
        first_name=spec["first_name"],
        last_name=spec["last_name"],
    )
    return ProviderState(
        user=user, roles={"refresh_token": str(RefreshToken.for_user(user))}
    )


def user_with_person() -> ProviderState:
    state = registered_user()
    geocoder = fixtures()["geocoder"]
    person = PersonRepository().create(
        state.user.username,
        {
            "first_name": "Grace",
            "last_name": "Hopper",
            "tag": "FRIEND",
            "city": "Milwaukee",
            "state": "WI",
            "country": "USA",
            "street": "500 N Harbor Dr",
            "birthday": "1906-12-09",
            "phone_number": "+14145550100",
            "pin_color": "#2196F3",
            "pin_style": "circle",
            "pin_icon_type": "emoji",
            "pin_emoji": "🚢",
            "contact_cadence_days": 14,
            "preferred_airport": 2364,
            "preferred_station": 1753,
            "lat": geocoder["lat"],
            "lng": geocoder["lng"],
            "timezone": geocoder["timezone"],
        },
    )
    state.roles["person"] = person.id
    return state


def user_with_contacted_person() -> ProviderState:
    state = user_with_person()
    log = ContactLogRepository().create(
        state.user.username,
        state.roles["person"],
        {
            "channel": "CALL",
            "contacted_at": "2026-10-20T18:30:00+00:00",
            "note": "Caught up about COBOL",
        },
    )
    state.roles["contact_log"] = log.id
    return state


def user_with_trip() -> ProviderState:
    state = user_with_person()
    geocoder = fixtures()["geocoder"]
    owner = state.user.username
    trips = TripRepository()
    trip = trips.create(
        owner,
        {
            "name": "Milwaukee weekend",
            "date": "2026-11-14",
            "start_date": "2026-11-14",
            "end_date": "2026-11-16",
            "status": "DRAFT",
        },
    )
    trips.replace_stops(
        trip.id,
        owner,
        [
            {
                "sequence_order": 0,
                "lat": geocoder["lat"],
                "lng": geocoder["lng"],
                "person_ids": [state.roles["person"]],
            },
            {
                "sequence_order": 1,
                "lat": 41.785999,
                "lng": -87.752403,
                "airport_id": 2364,
            },
        ],
    )
    trip = trips.get_for_owner(trip.id, owner)
    state.roles["trip"] = trip.id
    for index, stop in enumerate(trip.stops):
        state.roles[f"trip.stop.{index}"] = stop.id
    for index, leg in enumerate(trip.legs):
        state.roles[f"trip.leg.{index}"] = leg.id
    return state


STATES = {
    "anonymous": anonymous,
    "registered_user": registered_user,
    "user_with_person": user_with_person,
    "user_with_contacted_person": user_with_contacted_person,
    "user_with_trip": user_with_trip,
}

# The serializer that consumes each interaction's request body, for the check
# that the client sends nothing the server silently drops.
REQUEST_SERIALIZERS = {
    "auth.token": TokenObtainPairSerializer,
    "auth.token.invalid": TokenObtainPairSerializer,
    "auth.token.refresh": TokenRefreshSerializer,
    "auth.register": RegisterSerializer,
    "auth.register.invalid": RegisterSerializer,
    "auth.password_reset": PasswordResetRequestSerializer,
    "profile.update": UserProfileSerializer,
    "profile.upload_image": UserProfileSerializer,
    "people.create": PersonSerializer,
    "people.update": PersonSerializer,
    "contact_logs.create": ContactLogSerializer,
    "trips.create": TripSerializer,
    "trips.update": TripSerializer,
}

# Where an uploaded file must show up in the response. Upload parts are read
# from request.FILES by the views, not by a serializer, so they get their own
# check.
UPLOAD_POINTERS = {
    "profile.upload_image": {"profile_image": "/profile_image"},
    "people.create": {"profile_image": "/properties/profile_image"},
}
