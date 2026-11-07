"""Firestore round-trip budgets: every API route, at two sizes of data.

The API runs on AWS and Firestore on GCP, so every round trip is a
cross-cloud call, and a request's round trips run one after another. A request
whose round trips grow with the caller's data (one more query per friend, per
trip, per stop) gets slower and dearer for every user as they use the app,
and nothing else in the suites would notice: against the local emulator a
round trip costs about a millisecond.

Each case sends one request as the owner of the seeded data, twice: once with
a small account (one of everything) and once with a large one (many people,
contact logs, trips and stops, and a request body carrying more stops). The
number of RPCs must equal the case's budget both times, so it doesn't grow
with the data. Budgets are exact, like assertNumQueries: a change that saves
a round trip fails too, so the budget can be lowered to keep it.

A route whose round trips do grow is a known gap: its case gives the counts
at both sizes and the task that tracks it. Making it worse fails, and so does
fixing it, which is the prompt to move it to a flat budget.

The completeness test fails when a route and method the authorization matrix
lets the owner call has no case here.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from unittest.mock import MagicMock, patch

from django.contrib.auth.models import User
from django.urls import reverse
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from apps.common.testing import (
    FirestoreTestMixin,
    ThrottleIsolationMixin,
    count_firestore_rpcs,
    purge_collection,
)
from apps.people.repositories import ContactLogRepository, PersonRepository
from apps.trips.repositories import TripRepository
from apps.users.repositories import UserProfileRepository
from tests.test_authz_matrix import MATRIX

PASSWORD = "Budget!Pass123"
OWNER = "owner-b1"
LONDON = (51.5074, -0.1278, "Europe/London")
HEATHROW = 2364  # An airport id in airports_export.json.

# The routes that grow, recorded as found and being fixed in the same
# subtask: Performance & load tests.
GAP = "https://app.clickup.com/t/86bcqv0gd"

# How much the large account holds. Big enough that one query per item shows
# up as a different count, small enough to seed in about a second.
LARGE = {"people": 8, "logs_per_person": 3, "trips": 6, "stops_per_trip": 4}
SMALL = {"people": 1, "logs_per_person": 1, "trips": 1, "stops_per_trip": 2}


def point(lng, lat):
    return {"type": "Point", "coordinates": [lng, lat]}


@dataclass
class Seed:
    """The owner's records that the requests address."""

    size: dict
    user: User
    person: str
    people: list[str]
    log: str
    trip: str
    leg: str


def stops_payload(seed: Seed) -> list[dict]:
    """The stops a planner save sends: as many as the account's trips hold,
    each naming one of the account's people, the second at an airport."""
    return [
        {
            "sequence_order": order,
            "location": point(-0.12 + order, 51.5),
            "people": [seed.people[order % len(seed.people)]],
            "airport": HEATHROW if order == 1 else None,
        }
        for order in range(seed.size["stops_per_trip"])
    ]


@dataclass
class Budget:
    """The round trips one request may make.

    rpcs is the exact count at both sizes. A known gap gives the counts at
    each size instead, as (small, large), with the task tracking it.
    """

    url: Callable[[Seed], str]
    rpcs: int | None = None
    status: int = 200
    payload: Callable[[Seed], dict] | None = None
    known_gap: tuple[int, int] | None = None
    task: str | None = None
    # Set by the cases that only make sense on a fresh trip (booking).
    prepare: Callable[[Seed], None] | None = None

    def __post_init__(self):
        assert (self.rpcs is None) != (self.known_gap is None), (
            "a budget is either flat (rpcs) or a known gap"
        )
        assert (self.known_gap is None) == (self.task is None), (
            "a known gap names the task that tracks it"
        )


def _person_url(s):
    return reverse("person-detail", args=[s.person])


def _log_url(s):
    return reverse("contactlog-detail", args=[s.log])


def _trip_url(s):
    return reverse("trip-detail", args=[s.trip])


def _leg_url(s):
    return reverse("tripleg-detail", args=[s.leg])


def _registration(_seed):
    _registration.n += 1
    return {
        "username": f"budget-new-{_registration.n}",
        "email": f"budget-new-{_registration.n}@example.com",
        "password": PASSWORD,
        "password_confirm": PASSWORD,
    }


_registration.n = 0


def _new_person(_seed):
    return {"tag": "FRIEND", "first_name": "New", "city": "London", "country": "UK"}


def _book(seed: Seed):
    """Put the trip back in DRAFT, so the PATCH to BOOKED snapshots it."""
    TripRepository().update(seed.trip, OWNER, {"status": "DRAFT"})


# Keyed by (route name, method), with a suffix for a second case on the same
# route. Every (route, method) the owner may call in the authz matrix needs
# at least one case.
BUDGETS: dict[tuple[str, str], Budget] = {
    ("user_profile", "GET"): Budget(url=lambda s: reverse("user_profile"), rpcs=1),
    ("user_profile", "PATCH"): Budget(
        url=lambda s: reverse("user_profile"),
        payload=lambda s: {"city": "Leeds"},
        rpcs=3,
    ),
    # The auth routes read and write only Django's SQL tables.
    ("token_obtain_pair", "POST"): Budget(
        url=lambda s: reverse("token_obtain_pair"),
        payload=lambda s: {"username": OWNER, "password": PASSWORD},
        rpcs=0,
    ),
    ("token_refresh", "POST"): Budget(
        url=lambda s: reverse("token_refresh"),
        payload=lambda s: {"refresh": str(RefreshToken.for_user(s.user))},
        rpcs=0,
    ),
    ("register", "POST"): Budget(
        url=lambda s: reverse("register"), payload=_registration, status=201, rpcs=0
    ),
    ("password_reset", "POST"): Budget(
        url=lambda s: reverse("password_reset"),
        payload=lambda s: {"email": f"{OWNER}@example.com"},
        rpcs=0,
    ),
    ("password_reset_confirm", "POST"): Budget(
        url=lambda s: reverse("password_reset_confirm"),
        payload=lambda s: {
            "user_id": s.user.pk,
            "token": "not-a-real-token",
            "password": "Other!Pass987",
            "password_confirm": "Other!Pass987",
        },
        status=400,
        rpcs=0,
    ),
    ("person-list", "GET"): Budget(
        url=lambda s: reverse("person-list"), known_gap=(2, 9), task=GAP
    ),
    ("person-list", "POST"): Budget(
        url=lambda s: reverse("person-list"), payload=_new_person, status=201, rpcs=3
    ),
    ("person-detail", "GET"): Budget(url=_person_url, rpcs=2),
    ("person-detail", "PUT"): Budget(
        url=_person_url,
        payload=lambda s: {
            "tag": "FAMILY",
            "first_name": "Renamed",
            "city": "London",
            "country": "UK",
        },
        rpcs=4,
    ),
    ("person-detail", "PATCH"): Budget(
        url=_person_url, payload=lambda s: {"first_name": "Renamed"}, rpcs=4
    ),
    ("person-detail", "DELETE"): Budget(
        url=_person_url, status=204, known_gap=(4, 6), task=GAP
    ),
    ("contactlog-list", "GET"): Budget(
        url=lambda s: reverse("contactlog-list"), known_gap=(3, 17), task=GAP
    ),
    ("contactlog-list", "POST"): Budget(
        url=lambda s: reverse("contactlog-list"),
        payload=lambda s: {
            "person": s.person,
            "channel": "CALL",
            "contacted_at": "2026-10-01T12:00:00Z",
        },
        status=201,
        rpcs=3,
    ),
    ("contactlog-detail", "GET"): Budget(url=_log_url, known_gap=(3, 17), task=GAP),
    ("contactlog-detail", "PUT"): Budget(
        url=_log_url,
        payload=lambda s: {
            "person": s.person,
            "channel": "VIDEO",
            "contacted_at": "2026-10-02T12:00:00Z",
            "note": "rewritten",
        },
        known_gap=(5, 19),
        task=GAP,
    ),
    ("contactlog-detail", "PATCH"): Budget(
        url=_log_url,
        payload=lambda s: {"note": "rewritten"},
        known_gap=(5, 19),
        task=GAP,
    ),
    ("contactlog-detail", "DELETE"): Budget(
        url=_log_url, status=204, known_gap=(4, 18), task=GAP
    ),
    # The hub lookups search the in-memory reference data.
    ("nearest_airports", "GET"): Budget(
        url=lambda s: reverse("nearest_airports") + "?lat=51.5&lon=-0.12", rpcs=0
    ),
    ("nearest-stations", "GET"): Budget(
        url=lambda s: reverse("nearest-stations") + "?lat=51.5&lon=-0.12", rpcs=0
    ),
    ("trip-list", "GET"): Budget(
        url=lambda s: reverse("trip-list"), known_gap=(4, 14), task=GAP
    ),
    ("trip-list", "POST"): Budget(
        url=lambda s: reverse("trip-list"),
        payload=lambda s: {
            "name": "Planned",
            "date": "2026-11-14",
            "stops": stops_payload(s),
        },
        status=201,
        known_gap=(20, 22),
        task=GAP,
    ),
    ("trip-detail", "GET"): Budget(url=_trip_url, rpcs=5),
    ("trip-detail", "PUT"): Budget(
        url=_trip_url,
        payload=lambda s: {
            "name": "Replanned",
            "date": "2026-11-14",
            "stops": stops_payload(s),
        },
        known_gap=(22, 24),
        task=GAP,
    ),
    ("trip-detail", "PATCH"): Budget(
        url=_trip_url, payload=lambda s: {"name": "Renamed"}, rpcs=11
    ),
    # Booking freezes a snapshot of every stop's people and hub.
    ("trip-detail", "PATCH", "book"): Budget(
        url=_trip_url,
        payload=lambda s: {"status": "BOOKED"},
        prepare=_book,
        known_gap=(19, 25),
        task=GAP,
    ),
    ("trip-detail", "DELETE"): Budget(
        url=_trip_url, status=204, known_gap=(7, 11), task=GAP
    ),
    ("trip-stops", "GET"): Budget(
        url=lambda s: reverse("trip-stops", args=[s.trip]), rpcs=3
    ),
    ("trip-stops", "POST"): Budget(
        url=lambda s: reverse("trip-stops", args=[s.trip]),
        payload=lambda s: {"sequence_order": 99, "location": point(2.35, 48.85)},
        status=201,
        rpcs=12,
    ),
    ("trip-calculate-route", "POST"): Budget(
        url=lambda s: reverse("trip-calculate-route"),
        payload=lambda s: {"coordinates": [[-0.1278, 51.5074], [2.35, 48.85]]},
        rpcs=0,
    ),
    ("tripleg-list", "GET"): Budget(
        url=lambda s: reverse("tripleg-list"), known_gap=(5, 25), task=GAP
    ),
    ("tripleg-detail", "GET"): Budget(url=_leg_url, known_gap=(5, 25), task=GAP),
    ("tripleg-detail", "PATCH"): Budget(
        url=_leg_url,
        payload=lambda s: {"booking_reference": "ABC123"},
        known_gap=(9, 29),
        task=GAP,
    ),
    ("tripleg-smart-lookup", "POST"): Budget(
        url=lambda s: reverse("tripleg-smart-lookup", args=[s.leg]),
        payload=lambda s: {"identifier": "BA123"},
        known_gap=(9, 29),
        task=GAP,
    ),
}


@dataclass
class Measured:
    small: int
    large: int
    by_rpc: dict = field(default_factory=dict)


class BudgetBase(ThrottleIsolationMixin, FirestoreTestMixin, APITestCase):
    collections_to_purge = ["people", "trips", "user_profiles"]

    @classmethod
    def setUpTestData(cls):
        cls.user = User.objects.create_user(
            username=OWNER, password=PASSWORD, email=f"{OWNER}@example.com"
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

    def seed(self, size: dict) -> Seed:
        for name in self.collections_to_purge:
            purge_collection(name)
        people_repo = PersonRepository()
        logs_repo = ContactLogRepository()
        trips_repo = TripRepository()

        people = []
        last_log = None
        for n in range(size["people"]):
            person_id = people_repo.create(
                OWNER,
                {
                    "tag": "FRIEND",
                    "first_name": f"Friend {n}",
                    "city": "London",
                    "country": "UK",
                    "lat": 51.5 + n / 100,
                    "lng": -0.12,
                },
            ).id
            people.append(person_id)
            for day in range(size["logs_per_person"]):
                last_log = logs_repo.create(
                    OWNER,
                    person_id,
                    {
                        "channel": "CALL",
                        "contacted_at": f"2026-10-{day + 1:02d}T09:00:00+00:00",
                        "note": "",
                    },
                ).id

        trip_ids = []
        for n in range(size["trips"]):
            trip_id = trips_repo.create(
                OWNER, {"name": f"Trip {n}", "date": "2026-08-01"}
            ).id
            trip_ids.append(trip_id)
            trips_repo.replace_stops(
                trip_id,
                OWNER,
                [
                    {
                        "sequence_order": order,
                        "lat": 51.5,
                        "lng": -0.12 + order,
                        "person_ids": [people[order % len(people)]],
                        "airport_id": HEATHROW if order == 1 else None,
                    }
                    for order in range(size["stops_per_trip"])
                ],
            )
        # Queries return documents in id order, so a lookup that scans the
        # owner's trips until it finds one reaches this trip last: the worst
        # case, and the same count on every run.
        target_trip = max(trip_ids)
        leg = trips_repo.list_legs(target_trip, OWNER)[0].id
        trips_repo.update_leg(target_trip, leg, OWNER, {"transport_type": "FLIGHT"})
        UserProfileRepository().update(OWNER, {"city": "London"})

        return Seed(
            size=size,
            user=self.user,
            person=people[-1],
            people=people,
            log=last_log,
            trip=target_trip,
            leg=leg,
        )

    def measure(self, key, budget: Budget, size: dict) -> tuple[int, dict]:
        seed = self.seed(size)
        if budget.prepare is not None:
            budget.prepare(seed)
        url = budget.url(seed)
        payload = budget.payload(seed) if budget.payload else None
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {AccessToken.for_user(self.user)}"
        )
        method = key[1].lower()
        with count_firestore_rpcs() as counts:
            response = getattr(self.client, method)(url, payload, format="json")
        self.assertEqual(
            response.status_code,
            budget.status,
            f"{key[1]} {url}: {getattr(response, 'data', response.content)}",
        )
        return sum(counts.values()), dict(counts)


class RoundTripBudgetTests(BudgetBase):
    def test_every_route_stays_within_its_budget(self):
        for key, budget in BUDGETS.items():
            with self.subTest(case=" ".join(key)):
                small, small_by = self.measure(key, budget, SMALL)
                large, large_by = self.measure(key, budget, LARGE)
                label = (
                    f"{' '.join(key)}: {small} round trips with one of everything "
                    f"{small_by}, {large} with a large account {large_by}"
                )
                if budget.known_gap is None:
                    self.assertEqual(
                        (small, large),
                        (budget.rpcs, budget.rpcs),
                        f"{label}; the budget is {budget.rpcs} at both sizes.",
                    )
                else:
                    self.assertEqual(
                        (small, large),
                        budget.known_gap,
                        f"{label}; the known gap ({budget.task}) is "
                        f"{budget.known_gap}. If it no longer grows, give it a "
                        "flat budget.",
                    )


class BudgetCompletenessTests(APITestCase):
    def test_every_route_the_owner_can_call_has_a_budget(self):
        callable_by_owner = {
            (name, method)
            for name, route in MATRIX.items()
            for method, (_anon, owner, _other) in route.expect.items()
            if owner != 405
        }
        budgeted = {key[:2] for key in BUDGETS}
        self.assertEqual(
            sorted(callable_by_owner - budgeted),
            [],
            "These routes have no round-trip budget in "
            "tests/test_round_trip_budgets.py. Add a case, with the count from "
            "the failure message.",
        )
        self.assertEqual(
            sorted(budgeted - callable_by_owner),
            [],
            "BUDGETS lists routes or methods the owner can't call",
        )
