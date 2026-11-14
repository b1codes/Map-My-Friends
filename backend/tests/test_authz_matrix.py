"""Authorization matrix: every API route, every HTTP method, three callers.

The callers are an anonymous client, the owner of the seeded data ("owner-a")
and another signed-in user ("owner-b") who has data of their own. The table
below says what status each of them must get. Alongside the status, every
case checks two things that a status alone can't prove:

- No response to anyone but the owner contains the owner's data, found by a
  marker string planted in it and by the owner's document ids.
- A request that is refused leaves Firestore exactly as it was. A 404 on a
  cross-user PATCH is worthless if the write went through anyway.

The completeness test walks Django's URL resolver, so a new endpoint fails the
suite until someone decides who may call it and adds it to MATRIX.
"""

from __future__ import annotations

import itertools
import unittest
from collections.abc import Callable
from dataclasses import dataclass, field
from unittest.mock import MagicMock, patch

from django.conf import settings
from django.contrib.auth.models import User
from django.core.cache import cache
from django.urls import URLPattern, URLResolver, get_resolver, resolve, reverse
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from apps.common import firestore as fs
from apps.common.testing import (
    FirestoreTestMixin,
    ThrottleIsolationMixin,
    purge_collection,
)
from apps.people.repositories import ContactLogRepository, PersonRepository
from apps.trips.repositories import TripRepository
from apps.users.repositories import UserProfileRepository

# Planted in every piece of owner-a's data that a response could echo. If it
# shows up in a response to anyone else, that response leaked owner-a's data.
MARKER = "PRIVATE-A-7f3c"
PASSWORD = "Matrix!Pass123"

LONDON = (51.5074, -0.1278, "Europe/London")
CALLERS = ("anon", "owner", "other")
METHODS = ("GET", "POST", "PUT", "PATCH", "DELETE")

# Shorthands for methods a route doesn't support. Routes that require
# authentication check permissions before the method, so anonymous callers
# get 401 there; open routes answer 405 to everyone.
AUTH_ONLY_405 = (401, 405, 405)
OPEN_405 = (405, 405, 405)

_unique = itertools.count()


def point(lng, lat):
    return {"type": "Point", "coordinates": [lng, lat]}


@dataclass
class Seed:
    """Ids of the documents seeded for one round of requests."""

    user_a: User
    user_b: User
    person_a: str
    log_a: str
    trip_a: str
    stop_ids_a: list[str]
    leg_a: str
    person_b: str
    log_b: str
    trip_b: str
    leg_b: str
    person_public: str

    @property
    def owner_a_ids(self) -> list[str]:
        """Every id of owner-a's that no other caller should ever see."""
        return [self.person_a, self.log_a, self.trip_a, self.leg_a, *self.stop_ids_a]


@dataclass
class Route:
    """Who may call one named route, and with what.

    expect maps each method to the status for (anon, owner, other). payloads
    maps a method to a function of the Seed returning the request body; the
    same body goes to all three callers, so a refusal can only come from who
    is calling, not from what they sent.
    """

    url: Callable[[Seed], str]
    expect: dict[str, tuple[int, int, int]]
    payloads: dict[str, Callable[[Seed], dict]] = field(default_factory=dict)


def _registration(_seed):
    n = next(_unique)
    return {
        "username": f"matrix-new-{n}",
        "email": f"matrix-new-{n}@example.com",
        "password": PASSWORD,
        "password_confirm": PASSWORD,
    }


def _new_person(_seed):
    return {"tag": "FRIEND", "first_name": "New", "city": "London", "country": "UK"}


MATRIX: dict[str, Route] = {
    # The profile has no id in its URL: every signed-in caller reads and
    # writes their own, so "other" gets 200 on owner-b's profile.
    "user_profile": Route(
        url=lambda s: reverse("user_profile"),
        expect={
            "GET": (401, 200, 200),
            "POST": AUTH_ONLY_405,
            "PUT": AUTH_ONLY_405,
            "PATCH": (401, 200, 200),
            "DELETE": AUTH_ONLY_405,
        },
        payloads={"PATCH": lambda s: {"city": "Leeds"}},
    ),
    # Login, refresh, register and both password-reset steps are open to
    # everyone by design. The body decides the outcome, not the caller.
    "token_obtain_pair": Route(
        url=lambda s: reverse("token_obtain_pair"),
        expect={
            "GET": OPEN_405,
            "POST": (200, 200, 200),
            "PUT": OPEN_405,
            "PATCH": OPEN_405,
            "DELETE": OPEN_405,
        },
        payloads={"POST": lambda s: {"username": "owner-a", "password": PASSWORD}},
    ),
    "token_refresh": Route(
        url=lambda s: reverse("token_refresh"),
        expect={
            "GET": OPEN_405,
            "POST": (200, 200, 200),
            "PUT": OPEN_405,
            "PATCH": OPEN_405,
            "DELETE": OPEN_405,
        },
        # A fresh token per request: refresh tokens rotate and are
        # blacklisted after use.
        payloads={"POST": lambda s: {"refresh": str(RefreshToken.for_user(s.user_a))}},
    ),
    "register": Route(
        url=lambda s: reverse("register"),
        expect={
            "GET": OPEN_405,
            "POST": (201, 201, 201),
            "PUT": OPEN_405,
            "PATCH": OPEN_405,
            "DELETE": OPEN_405,
        },
        payloads={"POST": _registration},
    ),
    "password_reset": Route(
        url=lambda s: reverse("password_reset"),
        expect={
            "GET": OPEN_405,
            "POST": (200, 200, 200),
            "PUT": OPEN_405,
            "PATCH": OPEN_405,
            "DELETE": OPEN_405,
        },
        payloads={"POST": lambda s: {"email": "owner-a@example.com"}},
    ),
    # A wrong token is refused whoever sends it.
    "password_reset_confirm": Route(
        url=lambda s: reverse("password_reset_confirm"),
        expect={
            "GET": OPEN_405,
            "POST": (400, 400, 400),
            "PUT": OPEN_405,
            "PATCH": OPEN_405,
            "DELETE": OPEN_405,
        },
        payloads={
            "POST": lambda s: {
                "user_id": s.user_a.pk,
                "token": "not-a-real-token",
                "password": "Hijack!Pass987",
                "password_confirm": "Hijack!Pass987",
            }
        },
    ),
    # Listing people is public: anonymous callers get the unowned dataset,
    # signed-in callers get only their own people.
    "person-list": Route(
        url=lambda s: reverse("person-list"),
        expect={
            "GET": (200, 200, 200),
            "POST": (401, 201, 201),
            "PUT": AUTH_ONLY_405,
            "PATCH": AUTH_ONLY_405,
            "DELETE": AUTH_ONLY_405,
        },
        payloads={"POST": _new_person},
    ),
    # Retrieve is AllowAny too, so an anonymous caller gets 404 for an owned
    # person rather than 401: to them it doesn't exist.
    "person-detail": Route(
        url=lambda s: reverse("person-detail", args=[s.person_a]),
        expect={
            "GET": (404, 200, 404),
            "POST": AUTH_ONLY_405,
            "PUT": (401, 200, 404),
            "PATCH": (401, 200, 404),
            "DELETE": (401, 204, 404),
        },
        payloads={
            "PUT": lambda s: {
                "tag": "FAMILY",
                "first_name": "Mallory",
                "city": "London",
                "country": "UK",
            },
            "PATCH": lambda s: {"first_name": "Mallory"},
        },
    ),
    # Logging contact with someone else's person is a 400 (an invalid person
    # reference), not a 404, because the person id is in the body.
    "contactlog-list": Route(
        url=lambda s: reverse("contactlog-list"),
        expect={
            "GET": (401, 200, 200),
            "POST": (401, 201, 400),
            "PUT": AUTH_ONLY_405,
            "PATCH": AUTH_ONLY_405,
            "DELETE": AUTH_ONLY_405,
        },
        payloads={
            "POST": lambda s: {
                "person": s.person_a,
                "channel": "CALL",
                "contacted_at": "2026-10-01T12:00:00Z",
            }
        },
    ),
    "contactlog-detail": Route(
        url=lambda s: reverse("contactlog-detail", args=[s.log_a]),
        expect={
            "GET": (401, 200, 404),
            "POST": AUTH_ONLY_405,
            "PUT": (401, 200, 404),
            "PATCH": (401, 200, 404),
            "DELETE": (401, 204, 404),
        },
        payloads={
            "PUT": lambda s: {
                "person": s.person_a,
                "channel": "VIDEO",
                "contacted_at": "2026-10-02T12:00:00Z",
                "note": "rewritten",
            },
            "PATCH": lambda s: {"note": "rewritten"},
        },
    ),
    # The hub lookups read static reference data, but the views require a
    # signed-in caller, so anonymous callers get 401.
    "nearest_airports": Route(
        url=lambda s: reverse("nearest_airports") + "?lat=51.5&lon=-0.12",
        expect={
            "GET": (401, 200, 200),
            "POST": AUTH_ONLY_405,
            "PUT": AUTH_ONLY_405,
            "PATCH": AUTH_ONLY_405,
            "DELETE": AUTH_ONLY_405,
        },
    ),
    "nearest-stations": Route(
        url=lambda s: reverse("nearest-stations") + "?lat=51.5&lon=-0.12",
        expect={
            "GET": (401, 200, 200),
            "POST": AUTH_ONLY_405,
            "PUT": AUTH_ONLY_405,
            "PATCH": AUTH_ONLY_405,
            "DELETE": AUTH_ONLY_405,
        },
    ),
    "trip-list": Route(
        url=lambda s: reverse("trip-list"),
        expect={
            "GET": (401, 200, 200),
            "POST": (401, 201, 201),
            "PUT": AUTH_ONLY_405,
            "PATCH": AUTH_ONLY_405,
            "DELETE": AUTH_ONLY_405,
        },
        payloads={"POST": lambda s: {"name": "New trip", "date": "2026-09-01"}},
    ),
    "trip-detail": Route(
        url=lambda s: reverse("trip-detail", args=[s.trip_a]),
        expect={
            "GET": (401, 200, 404),
            "POST": AUTH_ONLY_405,
            "PUT": (401, 200, 404),
            "PATCH": (401, 200, 404),
            "DELETE": (401, 204, 404),
        },
        payloads={
            "PUT": lambda s: {"name": "Hijacked", "date": "2026-09-01"},
            "PATCH": lambda s: {"name": "Hijacked"},
        },
    ),
    # GET on someone else's trip's stops answers 200 with an empty list, not
    # 404: list_stops returns [] for any trip the caller doesn't own, and for
    # ids that don't exist at all. That's inconsistent with trip-detail but
    # leaks nothing (not even whether the trip exists), so it's encoded as is.
    # Adding a stop to someone else's trip is a 404.
    "trip-stops": Route(
        url=lambda s: reverse("trip-stops", args=[s.trip_a]),
        expect={
            "GET": (401, 200, 200),
            "POST": (401, 201, 404),
            "PUT": AUTH_ONLY_405,
            "PATCH": AUTH_ONLY_405,
            "DELETE": AUTH_ONLY_405,
        },
        payloads={
            "POST": lambda s: {"sequence_order": 9, "location": point(2.35, 48.85)}
        },
    ),
    # Routing touches no stored data, but it spends the OSRM quota, so it is
    # for signed-in callers only.
    "trip-calculate-route": Route(
        url=lambda s: reverse("trip-calculate-route"),
        expect={
            "GET": AUTH_ONLY_405,
            "POST": (401, 200, 200),
            "PUT": AUTH_ONLY_405,
            "PATCH": AUTH_ONLY_405,
            "DELETE": AUTH_ONLY_405,
        },
        payloads={
            "POST": lambda s: {"coordinates": [[-0.1278, 51.5074], [2.35, 48.85]]}
        },
    ),
    "tripleg-list": Route(
        url=lambda s: reverse("tripleg-list"),
        expect={
            "GET": (401, 200, 200),
            "POST": AUTH_ONLY_405,
            "PUT": AUTH_ONLY_405,
            "PATCH": AUTH_ONLY_405,
            "DELETE": AUTH_ONLY_405,
        },
    ),
    "tripleg-detail": Route(
        url=lambda s: reverse("tripleg-detail", args=[s.leg_a]),
        expect={
            "GET": (401, 200, 404),
            "POST": AUTH_ONLY_405,
            "PUT": AUTH_ONLY_405,
            "PATCH": (401, 200, 404),
            "DELETE": AUTH_ONLY_405,
        },
        payloads={"PATCH": lambda s: {"booking_reference": "HIJACK1"}},
    ),
    # The seeded leg is a FLIGHT and BA123 is a number the lookup stub knows,
    # so the owner's lookup finds data and writes it to the leg.
    "tripleg-smart-lookup": Route(
        url=lambda s: reverse("tripleg-smart-lookup", args=[s.leg_a]),
        expect={
            "GET": AUTH_ONLY_405,
            "POST": (401, 200, 404),
            "PUT": AUTH_ONLY_405,
            "PATCH": AUTH_ONLY_405,
            "DELETE": AUTH_ONLY_405,
        },
        payloads={"POST": lambda s: {"identifier": "BA123"}},
    ),
}

# DRF's DefaultRouter adds an "api-root" view at the root of each router. Each
# router here also registers a viewset at r"", whose list route matches the
# same path first, so the root view can never be reached. The completeness
# test checks that it stays shadowed rather than trusting this comment.
SHADOWED_ROUTE_NAMES = {"api-root"}
SHADOWED_ROOTS = {
    "/api/people/": "person-list",
    "/api/contact-logs/": "contactlog-list",
    "/api/trips/": "trip-list",
}


def _excluded_prefix(route: str) -> str | None:
    """Why a non-API route is outside the matrix, or None if it isn't."""
    # Django admin has its own staff-only session login, separate from the
    # API's JWT auth and permission classes.
    if route.startswith("admin/"):
        return "admin"
    # Uploaded media is served by static() only when DEBUG is on; production
    # serves it from storage, outside Django.
    if route.startswith(settings.MEDIA_URL.lstrip("/")):
        return "media"
    return None


def iter_routes(patterns=None, prefix=""):
    """Yield (full route, url name) for every pattern, depth first."""
    if patterns is None:
        patterns = get_resolver().url_patterns
    for pattern in patterns:
        if isinstance(pattern, URLResolver):
            yield from iter_routes(pattern.url_patterns, prefix + str(pattern.pattern))
        elif isinstance(pattern, URLPattern):
            yield prefix + str(pattern.pattern), pattern.name


def _tree(collection_ref) -> dict:
    """A collection's documents and their subcollections, as plain data."""
    return {
        doc.id: {
            "data": doc.to_dict(),
            "subcollections": {
                sub.id: _tree(sub) for sub in doc.reference.collections()
            },
        }
        for doc in collection_ref.stream()
    }


def firestore_snapshot() -> dict:
    return {
        name: _tree(fs.collection(name))
        for name in ("people", "trips", "user_profiles")
    }


class MatrixBase(ThrottleIsolationMixin, FirestoreTestMixin, APITestCase):
    collections_to_purge = ["people", "trips", "user_profiles"]

    @classmethod
    def setUpTestData(cls):
        # Created once per class: hashing passwords is the slow part.
        cls.user_a = User.objects.create_user(
            username="owner-a", password=PASSWORD, email="owner-a@example.com"
        )
        cls.user_b = User.objects.create_user(
            username="owner-b", password=PASSWORD, email="owner-b@example.com"
        )

    def setUp(self):
        super().setUp()
        # No test may reach Nominatim or OSRM.
        geocode = patch("apps.people.views.geocode_address", return_value=LONDON)
        geocode.start()
        self.addCleanup(geocode.stop)

        osrm_response = MagicMock()
        osrm_response.raise_for_status.return_value = None
        osrm_response.json.return_value = {
            "code": "Ok",
            "routes": [{"geometry": {"type": "LineString", "coordinates": []}}],
        }
        osrm = patch("apps.trips.services.requests.get", return_value=osrm_response)
        osrm.start()
        self.addCleanup(osrm.stop)

        self.seed = self.seed_data()

    def seed_data(self) -> Seed:
        for name in self.collections_to_purge:
            purge_collection(name)
        people = PersonRepository()
        logs = ContactLogRepository()
        trips = TripRepository()

        def person(owner, first_name):
            return people.create(
                owner,
                {
                    "tag": "FRIEND",
                    "first_name": first_name,
                    "city": "London",
                    "country": "UK",
                    "lat": 51.5,
                    "lng": -0.12,
                },
            ).id

        def log(owner, person_id, note):
            return logs.create(
                owner,
                person_id,
                {
                    "channel": "CALL",
                    "contacted_at": "2026-10-01T09:00:00+00:00",
                    "note": note,
                },
            ).id

        def trip(owner, name, person_id):
            trip_id = trips.create(owner, {"name": name, "date": "2026-08-01"}).id
            trips.update(
                trip_id,
                owner,
                {},
                stops=[
                    {"sequence_order": 0, "lat": 51.5, "lng": -0.12},
                    {
                        "sequence_order": 1,
                        "lat": 48.85,
                        "lng": 2.35,
                        "person_ids": [person_id],
                    },
                ],
            )
            return trip_id

        person_a = person("owner-a", f"Alice {MARKER}")
        person_b = person("owner-b", "Bob")
        trip_a = trip("owner-a", f"Trip {MARKER}", person_a)
        trip_b = trip("owner-b", "Bob's trip", person_b)
        (leg_a,) = trips.get_for_owner(trip_a, "owner-a").legs
        (leg_b,) = trips.get_for_owner(trip_b, "owner-b").legs
        trips.patch_leg(
            leg_a, {"transport_type": "FLIGHT", "booking_reference": MARKER}
        )
        UserProfileRepository().get_or_create("owner-a")
        UserProfileRepository().update("owner-a", {"city": MARKER})

        seed = Seed(
            user_a=self.user_a,
            user_b=self.user_b,
            person_a=person_a,
            log_a=log("owner-a", person_a, f"Note {MARKER}"),
            trip_a=trip_a,
            stop_ids_a=[stop.id for stop in trips.list_stops(trip_a, "owner-a")],
            leg_a=leg_a.id,
            person_b=person_b,
            log_b=log("owner-b", person_b, "Bob's note"),
            trip_b=trip_b,
            leg_b=leg_b.id,
            person_public=person(None, "Public"),
        )
        self.baseline = firestore_snapshot()
        return seed

    def as_caller(self, caller: str):
        """Sign in with a real SimpleJWT access token, so the whole
        authentication stack runs, not a forced user."""
        self.client.credentials()
        if caller == "owner":
            token = AccessToken.for_user(self.user_a)
        elif caller == "other":
            token = AccessToken.for_user(self.user_b)
        else:
            return
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")

    def send(self, method: str, url: str, payload=None):
        return getattr(self.client, method.lower())(url, payload, format="json")

    def assert_no_owner_a_data(self, response, label):
        body = response.content.decode()
        self.assertNotIn(MARKER, body, f"{label} leaked owner-a's data")
        for doc_id in self.seed.owner_a_ids:
            self.assertNotIn(doc_id, body, f"{label} leaked owner-a's id {doc_id}")


class AuthorizationMatrixTests(MatrixBase):
    def test_every_route_method_and_caller(self):
        for name, route in MATRIX.items():
            for method in METHODS:
                for caller, expected in zip(CALLERS, route.expect[method], strict=True):
                    with self.subTest(route=name, method=method, caller=caller):
                        self._check_case(route, method, caller, expected)

    def _check_case(self, route, method, caller, expected):
        label = f"{method} {route.url(self.seed)} as {caller}"
        url = route.url(self.seed)
        payload_for = route.payloads.get(method)
        payload = payload_for(self.seed) if payload_for else None
        # Every case is one request in isolation; without this the anonymous
        # cases would run into the 10/minute burst throttle on the auth
        # routes, which test_throttling covers on its own.
        cache.clear()
        self.as_caller(caller)

        before = firestore_snapshot() if method != "GET" else None
        response = self.send(method, url, payload)

        self.assertEqual(response.status_code, expected, f"{label}: {response.data}")
        if caller != "owner":
            self.assert_no_owner_a_data(response, label)
        if before is not None and response.status_code >= 400:
            self.assertEqual(
                firestore_snapshot(), before, f"{label} was refused but changed data"
            )
        # A write went through: start the next case from clean data, so it
        # isn't testing against an already-deleted or renamed record.
        wrote = method != "GET" and response.status_code < 400
        if wrote and firestore_snapshot() != self.baseline:
            self.seed = self.seed_data()


class RouteCompletenessTests(APITestCase):
    def test_every_route_is_in_the_matrix(self):
        unlisted = []
        for route, name in iter_routes():
            if _excluded_prefix(route) or name in SHADOWED_ROUTE_NAMES:
                continue
            if name not in MATRIX:
                unlisted.append(f"{name or '<unnamed>'} ({route})")
        self.assertEqual(
            unlisted,
            [],
            "These routes have no row in MATRIX in tests/test_authz_matrix.py. "
            "Decide what anonymous callers, the owner and other users should "
            "get from each method, and add them.",
        )

    def test_matrix_lists_no_stale_routes(self):
        names = {name for _route, name in iter_routes()}
        self.assertEqual(
            sorted(set(MATRIX) - names),
            [],
            "MATRIX lists routes that no longer exist",
        )

    def test_every_matrix_row_covers_every_method(self):
        for name, route in MATRIX.items():
            with self.subTest(route=name):
                self.assertEqual(sorted(route.expect), sorted(METHODS))
                for method, statuses in route.expect.items():
                    self.assertEqual(len(statuses), len(CALLERS), method)

    def test_router_root_views_stay_shadowed(self):
        """api-root is skipped above only because nothing can reach it."""
        for path, list_route in SHADOWED_ROOTS.items():
            with self.subTest(path=path):
                self.assertEqual(resolve(path).url_name, list_route)


class FormatSuffixTests(MatrixBase):
    """Routers also register every route with a .json style suffix. Those
    are separate URL patterns on the same views, so check they enforce the
    same rules rather than assume it.

    They don't work at all yet: the viewset actions take (request, pk=None)
    and no format argument, so any suffixed request that gets past the
    permission check raises TypeError, a 500. The client is told to return
    that 500 instead of re-raising, so the ownership test can still run.
    """

    def setUp(self):
        super().setUp()
        self.client.raise_request_exception = False

    def suffixed_cases(self):
        """(route name, pk, GET statuses for anon/owner/other) as the
        unsuffixed routes answer them in MATRIX."""
        return [
            ("person-list", None, (200, 200, 200)),
            ("person-detail", self.seed.person_a, (404, 200, 404)),
            ("contactlog-list", None, (401, 200, 200)),
            ("contactlog-detail", self.seed.log_a, (401, 200, 404)),
            ("trip-list", None, (401, 200, 200)),
            ("trip-detail", self.seed.trip_a, (401, 200, 404)),
            ("trip-stops", self.seed.trip_a, (401, 200, 200)),
            ("tripleg-list", None, (401, 200, 200)),
            ("tripleg-detail", self.seed.leg_a, (401, 200, 404)),
        ]

    def suffixed_url(self, name, pk):
        kwargs = {"format": "json"}
        if pk is not None:
            kwargs["pk"] = pk
        return reverse(name, kwargs=kwargs)

    def test_suffixed_routes_never_serve_owner_a_data_to_others(self):
        for name, pk, _statuses in self.suffixed_cases():
            url = self.suffixed_url(name, pk)
            for caller in ("anon", "other"):
                with self.subTest(route=name, caller=caller):
                    self.as_caller(caller)
                    response = self.client.get(url)
                    self.assert_no_owner_a_data(response, f"{url} as {caller}")
                    if pk is not None and name != "trip-stops":
                        self.assertGreaterEqual(response.status_code, 400)

    # Bug: PersonViewSet, ContactLogViewSet, TripViewSet and TripLegViewSet
    # actions don't accept the `format` kwarg the router passes for .json
    # URLs, so every suffixed request past the permission check is a 500.
    # Filed as ClickUp 86bcz9b5y.
    @unittest.expectedFailure
    def test_suffixed_routes_answer_like_unsuffixed_ones(self):
        for name, pk, statuses in self.suffixed_cases():
            url = self.suffixed_url(name, pk)
            for caller, expected in zip(CALLERS, statuses, strict=True):
                with self.subTest(route=name, caller=caller):
                    self.as_caller(caller)
                    self.assertEqual(self.client.get(url).status_code, expected)


class ReservedIdTests(MatrixBase):
    """An id Firestore rejects outright (__name__ style) can't name anyone's
    record, so it should be a plain 404 like any other unknown id."""

    def setUp(self):
        super().setUp()
        self.client.raise_request_exception = False
        self.as_caller("owner")

    def test_people_contact_logs_and_legs_treat_reserved_ids_as_not_found(self):
        for name in ("person-detail", "contactlog-detail", "tripleg-detail"):
            with self.subTest(route=name):
                response = self.client.get(reverse(name, args=["__x__"]))
                self.assertEqual(response.status_code, 404)

    # Reserved ids used to reach Firestore and come back as a 500. They now
    # answer like any trip the caller doesn't own: detail is a 404, and stops
    # an empty list (see the matrix's note on other users' stops).
    def test_trips_treat_reserved_ids_as_not_found(self):
        detail = self.client.get(reverse("trip-detail", args=["__x__"]))
        self.assertEqual(detail.status_code, 404)

        stops = self.client.get(reverse("trip-stops", args=["__x__"]))
        self.assertEqual(stops.status_code, 200)
        self.assertEqual(stops.data, [])

    # Over Firestore's 1,500-byte limit. These reached the client, which
    # retried for five minutes before a 500 (found by the API fuzz test).
    def test_ids_too_long_for_firestore_are_not_found(self):
        long_id = "x" * 1501
        for name, method in (
            ("person-detail", "get"),
            ("person-detail", "delete"),
            ("contactlog-detail", "get"),
            ("contactlog-detail", "delete"),
            ("trip-detail", "get"),
            ("trip-detail", "delete"),
            ("tripleg-detail", "get"),
            ("tripleg-smart-lookup", "post"),
        ):
            with self.subTest(route=name, method=method):
                url = reverse(name, args=[long_id])
                response = getattr(self.client, method)(url, {}, format="json")
                self.assertEqual(response.status_code, 404)
        stops = self.client.get(reverse("trip-stops", args=[long_id]))
        self.assertEqual(stops.data, [])


class DatasetVisibilityTests(MatrixBase):
    """Who sees which people. Anonymous callers get the public (unowned)
    dataset; a signed-in user gets exactly their own people and nothing
    else, not even the public ones."""

    def person_ids(self, response):
        self.assertEqual(response.status_code, 200)
        return {feature["id"] for feature in response.data["features"]}

    def test_people_list_by_caller(self):
        expected = {
            "anon": {self.seed.person_public},
            "owner": {self.seed.person_a},
            "other": {self.seed.person_b},
        }
        for caller, ids in expected.items():
            with self.subTest(caller=caller):
                self.as_caller(caller)
                response = self.client.get(reverse("person-list"))
                self.assertEqual(self.person_ids(response), ids)

    def test_a_person_created_by_a_user_never_reaches_anonymous_callers(self):
        self.as_caller("owner")
        created = self.client.post(
            reverse("person-list"),
            {"tag": "FRIEND", "first_name": MARKER, "city": "London"},
            format="json",
        )
        self.assertEqual(created.status_code, 201)
        self.assertEqual(created.data["properties"]["owner"], "owner-a")

        self.as_caller("anon")
        listing = self.client.get(reverse("person-list"))
        self.assertNotIn(created.data["id"], self.person_ids(listing))
        self.assertNotIn(MARKER, listing.content.decode())
        detail = self.client.get(reverse("person-detail", args=[created.data["id"]]))
        self.assertEqual(detail.status_code, 404)

    def test_public_person_is_readable_anonymously_but_not_writable(self):
        url = reverse("person-detail", args=[self.seed.person_public])
        before = firestore_snapshot()

        self.as_caller("anon")
        self.assertEqual(self.client.get(url).status_code, 200)
        for method in ("PUT", "PATCH", "DELETE"):
            with self.subTest(caller="anon", method=method):
                self.assertEqual(
                    self.send(method, url, {"tag": "FRIEND"}).status_code, 401
                )

        # The public dataset belongs to nobody, so signed-in users can't see
        # or change it either: their owner key never matches None.
        self.as_caller("other")
        self.assertEqual(self.client.get(url).status_code, 404)
        for method in ("PUT", "PATCH", "DELETE"):
            with self.subTest(caller="other", method=method):
                self.assertEqual(
                    self.send(method, url, {"tag": "FRIEND"}).status_code, 404
                )

        self.assertEqual(firestore_snapshot(), before)

    def test_lists_return_only_the_callers_own_records(self):
        self.as_caller("other")
        cases = {
            "contactlog-list": {self.seed.log_b},
            "trip-list": {self.seed.trip_b},
            "tripleg-list": {self.seed.leg_b},
        }
        for name, ids in cases.items():
            with self.subTest(route=name):
                response = self.client.get(reverse(name))
                self.assertEqual(response.status_code, 200)
                self.assertEqual({row["id"] for row in response.data}, ids)


class CrossUserReferenceTests(MatrixBase):
    """IDOR through references in a request body rather than the URL: owner-b
    naming owner-a's ids inside their own records."""

    def setUp(self):
        super().setUp()
        self.as_caller("other")

    def test_trip_stop_naming_another_users_person_exposes_nothing(self):
        stops_url = reverse("trip-stops", args=[self.seed.trip_b])
        response = self.client.post(
            stops_url,
            {
                "sequence_order": 5,
                "location": point(2.35, 48.85),
                "people": [self.seed.person_a],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["people_detail"], [])
        self.assertNotIn(MARKER, response.content.decode())

        # Booking the trip snapshots each stop's people; owner-a's person must
        # not be copied into owner-b's snapshot. (owner-b's seeded stop names
        # owner-b's own person, which is fine and does show up.)
        trip_url = reverse("trip-detail", args=[self.seed.trip_b])
        booked = self.client.patch(trip_url, {"status": "BOOKED"}, format="json")
        self.assertEqual(booked.status_code, 200)
        for stop in booked.data["stops"]:
            detail_ids = [p["id"] for p in stop["people_detail"]]
            snapshot_ids = [p["id"] for p in stop["snapshot_metadata"]["people"]]
            self.assertNotIn(self.seed.person_a, detail_ids)
            self.assertNotIn(self.seed.person_a, snapshot_ids)
        self.assertNotIn(MARKER, booked.content.decode())

    def test_trip_update_cannot_patch_another_users_leg_by_id(self):
        before = firestore_snapshot()["trips"][self.seed.trip_a]
        response = self.client.patch(
            reverse("trip-detail", args=[self.seed.trip_b]),
            {"legs": [{"id": self.seed.leg_a, "booking_reference": "HIJACK"}]},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(firestore_snapshot()["trips"][self.seed.trip_a], before)

    def test_contact_log_update_cannot_move_a_log_onto_another_users_person(self):
        before = firestore_snapshot()["people"][self.seed.person_a]
        response = self.client.patch(
            reverse("contactlog-detail", args=[self.seed.log_b]),
            {"person": self.seed.person_a, "note": "moved"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["person"], self.seed.person_b)
        self.assertEqual(firestore_snapshot()["people"][self.seed.person_a], before)

    def test_records_cannot_be_created_on_another_users_behalf(self):
        """The owner comes from the token, never from the body."""
        person = self.client.post(
            reverse("person-list"),
            {"tag": "FRIEND", "first_name": "Planted", "owner": "owner-a"},
            format="json",
        )
        trip = self.client.post(
            reverse("trip-list"),
            {"name": "Planted", "date": "2026-09-01", "user": "owner-a"},
            format="json",
        )
        self.assertEqual(person.status_code, 201)
        self.assertEqual(person.data["properties"]["owner"], "owner-b")
        self.assertEqual(trip.status_code, 201)
        self.assertEqual(trip.data["user"], "owner-b")

        self.as_caller("owner")
        people = self.client.get(reverse("person-list")).data["features"]
        trips = self.client.get(reverse("trip-list")).data
        self.assertEqual([p["id"] for p in people], [self.seed.person_a])
        self.assertEqual([t["id"] for t in trips], [self.seed.trip_a])

    def test_profile_patch_only_touches_the_callers_profile(self):
        before = firestore_snapshot()["user_profiles"]["owner-a"]
        response = self.client.patch(
            reverse("user_profile"), {"city": "Leeds"}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["username"], "owner-b")
        self.assertEqual(firestore_snapshot()["user_profiles"]["owner-a"], before)
