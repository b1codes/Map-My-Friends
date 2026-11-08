"""Property-based fuzzing of every API route, with Hypothesis.

Each route and method gets requests generated from a valid one: the body
the app really sends (from contracts/api/interactions, or the authorization
matrix) with fields dropped, swapped for random JSON, or joined by extra
ones; nested stops and legs mutated the same way; ids in the path that are
real, someone else's, or junk; query strings of any shape; and callers
signed in, signed out, or holding a garbage or forged token. Every answer
must hold to three properties:

- Never a 5xx, and never an unhandled exception (the test client re-raises
  those).
- A refusal (4xx) from an API view is empty or JSON, which is what the
  app parses.
- A success (2xx) that the app depends on matches its contract schema in
  contracts/api/schema.json, so whatever was accepted reads back in a shape
  the app can parse.

Profiles (FUZZ_PROFILE): "pr" (the default) is derandomized, the same 50
requests per route on every run, about 15 seconds in all. "nightly" draws
5,000 per route from a random seed, about 15 minutes. Set FUZZ_SEED to
replay one. Either way, a failure prints the minimal falsifying request.
See docs/testing.md (Monkey and fuzz tests).
"""

from __future__ import annotations

import json
import os
from collections.abc import Callable
from dataclasses import dataclass
from unittest.mock import patch
from urllib.parse import quote, unquote, urlencode

import jwt
from django.core.cache import cache
from django.test import SimpleTestCase
from django.urls import Resolver404, resolve, reverse
from hypothesis import HealthCheck, given, seed, settings
from hypothesis import strategies as st
from hypothesis.extra.django import TestCase as HypothesisTestCase
from rest_framework.throttling import SimpleRateThrottle
from rest_framework_simplejwt.tokens import AccessToken

from tests.contracts.support import (
    api_validator,
    fixtures,
    interactions,
    schema_errors,
    substitute,
)
from tests.test_authz_matrix import MATRIX, MatrixBase, Seed

PROFILE = os.environ.get("FUZZ_PROFILE", "pr")
settings.register_profile(
    "pr",
    max_examples=50,
    derandomize=True,
    database=None,
    deadline=None,
    print_blob=True,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
settings.register_profile(
    "nightly",
    max_examples=5000,
    database=None,
    deadline=None,
    print_blob=True,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
FUZZ = settings.get_profile(PROFILE)
FUZZ_SEED = os.environ.get("FUZZ_SEED")


def fuzz(test):
    """@given's settings, plus a fixed seed when FUZZ_SEED is set."""
    test = FUZZ(test)
    return seed(int(FUZZ_SEED))(test) if FUZZ_SEED else test


# ---------------------------------------------------------------------------
# Values
# ---------------------------------------------------------------------------

# Strings that have broken APIs before: empty and blank, NUL, huge, path and
# Firestore-reserved shapes, numbers and literals as text, impossible dates,
# and scripts and emoji. Lone surrogates are valid JSON escapes but not
# valid UTF-8, which is all Firestore stores.
NASTY_STRINGS = [
    "",
    " ",
    "\x00",
    "\ud800",
    "a\udfffb",
    "x" * 10_000,
    "__name__",
    "__x__",
    "/",
    "../..",
    "a/b",
    ".",
    "0",
    "-1",
    "1e309",
    "NaN",
    "null",
    "true",
    "2026-02-30",
    "0000-01-01",
    "9999-12-31T23:59:59Z",
    "2026-13-01T25:61:00+99:00",
    "🦄👩🏽‍💻",
    "نور",
    "' OR 1=1 --",
    "<script>alert(1)</script>",
    "%s%n",
    "FRIEND",
    "FLIGHT",
    "BOOKED",
    "CALL",
]

scalars = st.one_of(
    st.none(),
    st.booleans(),
    st.integers(min_value=-(2**70), max_value=2**70),
    st.floats(allow_nan=True, allow_infinity=True),
    st.sampled_from(NASTY_STRINGS),
    st.text(max_size=40),
    st.text(st.characters(categories=["Cs", "Cc", "Zs", "So"]), max_size=8),
)

json_values = st.recursive(
    scalars,
    lambda children: st.one_of(
        st.lists(children, max_size=4),
        st.dictionaries(st.text(max_size=12), children, max_size=4),
    ),
    max_leaves=12,
)


@st.composite
def mutated(draw, value):
    """[value], changed the way a confused or hostile client would change it,
    mostly a little and sometimes completely."""
    roll = draw(st.integers(0, 9))
    if roll == 0:
        return draw(json_values)
    if isinstance(value, dict):
        out = {}
        for key, item in value.items():
            op = draw(st.sampled_from(["keep", "keep", "mutate", "drop", "null"]))
            if op == "keep":
                out[key] = item
            elif op == "mutate":
                out[key] = draw(mutated(item))
            elif op == "null":
                out[key] = None
        extra_keys = st.one_of(st.sampled_from(KNOWN_FIELDS), st.text(max_size=10))
        out.update(draw(st.dictionaries(extra_keys, json_values, max_size=2)))
        return out
    if isinstance(value, list):
        items = [draw(mutated(item)) for item in value]
        if items and draw(st.booleans()):
            items = items * draw(st.integers(1, 3))
        if draw(st.integers(0, 4)) == 0:
            items.append(draw(json_values))
        return items
    return value if roll < 6 else draw(scalars)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


def _contract_body(interaction_id: str, s: Seed) -> dict:
    """A contract request body, its placeholder ids swapped for seeded ones."""
    body = next(i for i in interactions() if i.id == interaction_id).request_body()
    ids = {
        "person": s.person_a,
        "contact_log": s.log_a,
        "trip": s.trip_a,
        "trip.stop.0": s.stop_ids_a[0],
        "trip.stop.1": s.stop_ids_a[1],
        "trip.leg.0": s.leg_a,
    }
    placeholders = fixtures()["placeholders"]
    return substitute(
        body,
        {
            placeholder: ids[role]
            for placeholder, role in placeholders.items()
            if role in ids
        },
    )


@dataclass
class Target:
    """One route to fuzz: its URL (given an id), whether it takes one, and
    a valid body for each method that has one."""

    name: str
    methods: tuple[str, ...]
    url: Callable[[str | None], str]
    ids: Callable[[Seed], list[str]] | None = None
    bodies: dict[str, Callable[[Seed], dict]] | None = None
    query: dict[str, str] | None = None


def _detail(name):
    return lambda pk: reverse(name, args=[pk])


def _list(name):
    return lambda _pk: reverse(name)


def _matrix_body(route, method):
    return lambda s: MATRIX[route].payloads[method](s)


TARGETS = [
    Target(
        "user_profile",
        ("GET", "PATCH"),
        _list("user_profile"),
        bodies={"PATCH": lambda s: _contract_body("profile.update", s)},
    ),
    Target(
        "token_obtain_pair",
        ("POST",),
        _list("token_obtain_pair"),
        bodies={"POST": _matrix_body("token_obtain_pair", "POST")},
    ),
    Target(
        "token_refresh",
        ("POST",),
        _list("token_refresh"),
        bodies={"POST": _matrix_body("token_refresh", "POST")},
    ),
    Target(
        "register",
        ("POST",),
        _list("register"),
        bodies={"POST": lambda s: _contract_body("auth.register", s)},
    ),
    Target(
        "password_reset",
        ("POST",),
        _list("password_reset"),
        bodies={"POST": _matrix_body("password_reset", "POST")},
    ),
    Target(
        "password_reset_confirm",
        ("POST",),
        _list("password_reset_confirm"),
        bodies={"POST": _matrix_body("password_reset_confirm", "POST")},
    ),
    Target(
        "person-list",
        ("GET", "POST"),
        _list("person-list"),
        bodies={"POST": lambda s: _contract_body("people.create", s)},
    ),
    Target(
        "person-detail",
        ("GET", "PUT", "PATCH", "DELETE"),
        _detail("person-detail"),
        ids=lambda s: [s.person_a, s.person_b, s.person_public],
        bodies={
            "PUT": lambda s: _contract_body("people.update", s),
            "PATCH": lambda s: _contract_body("people.update", s),
        },
    ),
    Target(
        "contactlog-list",
        ("GET", "POST"),
        _list("contactlog-list"),
        bodies={"POST": lambda s: _contract_body("contact_logs.create", s)},
        query={"person": "person"},
    ),
    Target(
        "contactlog-detail",
        ("GET", "PUT", "PATCH", "DELETE"),
        _detail("contactlog-detail"),
        ids=lambda s: [s.log_a, s.log_b],
        bodies={
            "PUT": _matrix_body("contactlog-detail", "PUT"),
            "PATCH": _matrix_body("contactlog-detail", "PATCH"),
        },
    ),
    Target(
        "nearest_airports",
        ("GET",),
        _list("nearest_airports"),
        query={"lat": "43.0389", "lon": "-87.9065", "count": "3"},
    ),
    Target(
        "nearest-stations",
        ("GET",),
        _list("nearest-stations"),
        query={"lat": "43.0389", "lon": "-87.9065", "count": "3"},
    ),
    Target(
        "trip-list",
        ("GET", "POST"),
        _list("trip-list"),
        bodies={"POST": lambda s: _contract_body("trips.create", s)},
    ),
    Target(
        "trip-detail",
        ("GET", "PUT", "PATCH", "DELETE"),
        _detail("trip-detail"),
        ids=lambda s: [s.trip_a, s.trip_b],
        bodies={
            "PUT": lambda s: _contract_body("trips.update", s),
            "PATCH": lambda s: _contract_body("trips.update", s),
        },
    ),
    Target(
        "trip-stops",
        ("GET", "POST"),
        _detail("trip-stops"),
        ids=lambda s: [s.trip_a, s.trip_b],
        bodies={"POST": _matrix_body("trip-stops", "POST")},
    ),
    Target(
        "trip-calculate-route",
        ("POST",),
        _list("trip-calculate-route"),
        bodies={"POST": _matrix_body("trip-calculate-route", "POST")},
    ),
    Target("tripleg-list", ("GET",), _list("tripleg-list")),
    Target(
        "tripleg-detail",
        ("GET", "PATCH"),
        _detail("tripleg-detail"),
        ids=lambda s: [s.leg_a, s.leg_b],
        bodies={
            "PATCH": lambda s: next(
                leg
                for leg in _contract_body("trips.update", s)["legs"]
                if leg["id"] == s.leg_a
            )
        },
    ),
    Target(
        "tripleg-smart-lookup",
        ("POST",),
        _detail("tripleg-smart-lookup"),
        ids=lambda s: [s.leg_a, s.leg_b],
        bodies={"POST": _matrix_body("tripleg-smart-lookup", "POST")},
    ),
]

# Every field name any request carries, for "extra field" mutations.
KNOWN_FIELDS = sorted(
    {
        key
        for interaction in interactions()
        for key in (interaction.request_body() or {})
    }
    | {"id", "user", "owner", "owner_key", "lat", "lng", "stops", "legs", "is_staff"}
)

# The contract schema for each (url name, method, status, signed in?) the
# app parses. A contract describes the caller it was written for: the app
# never lists people signed out, so the anonymous answer (which leaves out
# contact history, by design) isn't held to the signed-in schema.
CONTRACT_SCHEMAS: dict[tuple[str, str, int, bool], str] = {}
for _interaction in interactions():
    _request = _interaction.request
    _schema = _interaction.response.get("schema")
    if not _schema:
        continue
    CONTRACT_SCHEMAS[
        (
            resolve("/api/" + _request["path"]).url_name,
            _request["method"],
            _interaction.response["status"],
            _request.get("auth") == "user",
        )
    ] = _schema


# ---------------------------------------------------------------------------
# Callers and requests
# ---------------------------------------------------------------------------


def _forged_auth0(payload: dict) -> str:
    """A token with Auth0's issuer, signed with a key Auth0 never issued."""
    # The issuer last, so a generated "iss" claim can't replace it (PyJWT
    # refuses to sign a non-string issuer).
    return jwt.encode(
        {**payload, "iss": "https://map-my-friends.us.auth0.com/"},
        "not-auth0",
        algorithm="HS256",
    )


callers = st.sampled_from(["owner", "owner", "owner", "other", "anon", "junk"])
junk_tokens = st.one_of(
    st.sampled_from(["", "Bearer", "Bearer ", "Basic Zm9vOmJhcg==", "Bearer a.b.c"]),
    st.text(max_size=60).map(lambda t: f"Bearer {t}"),
    st.dictionaries(st.text(max_size=5), json_values, max_size=3).map(
        lambda p: f"Bearer {_forged_auth0(p)}"
    ),
)
encodings = st.sampled_from(["json", "json", "json", "json", "broken", "form"])


def _quoted(pk: str) -> str:
    """[pk] as it would appear in a URL: its UTF-8 bytes, percent-encoded,
    including the invalid ones a lone surrogate stands for."""
    return quote(pk.encode("utf-8", "surrogatepass"), safe="")


@dataclass
class Sent:
    method: str
    path: str
    status: int
    body: bytes
    content_type: str


class ApiFuzzTests(MatrixBase, HypothesisTestCase):
    """One test per route, so each starts from freshly seeded data. Each
    example runs in its own database transaction (Hypothesis's TestCase), so
    accounts one example registers don't leak into the next."""

    def setUp(self):
        super().setUp()
        # Rate limits have their own tests; here they'd turn most examples
        # into 429s.
        throttle = patch.object(SimpleRateThrottle, "allow_request", return_value=True)
        throttle.start()
        self.addCleanup(throttle.stop)
        # A forged Auth0 token makes the API fetch Auth0's signing keys. No
        # test may reach Auth0: fail the fetch, as it fails offline.
        jwks = patch(
            "apps.users.auth.PyJWKClient.get_signing_key_from_jwt",
            side_effect=jwt.PyJWKClientError("offline (fuzz test)"),
        )
        jwks.start()
        self.addCleanup(jwks.stop)

    def _sign_in(self, caller: str, token: str):
        self.client.credentials()
        if caller == "owner":
            self.client.credentials(
                HTTP_AUTHORIZATION=f"Bearer {AccessToken.for_user(self.user_a)}"
            )
        elif caller == "other":
            self.client.credentials(
                HTTP_AUTHORIZATION=f"Bearer {AccessToken.for_user(self.user_b)}"
            )
        elif caller == "junk":
            # A header is bytes on the wire, and WSGI hands them over as
            # latin-1. Send the token's UTF-8 bytes, which is what a client
            # typing it would put on the wire, invalid sequences included.
            self.client.credentials(
                HTTP_AUTHORIZATION=token.encode("utf-8", "surrogatepass").decode(
                    "latin-1"
                )
            )

    def _send(self, method, path, body, encoding) -> Sent:
        if body is None:
            data, content_type = b"", "application/json"
        elif encoding == "broken":
            text = json.dumps(body, allow_nan=True)
            data, content_type = (
                text[: max(1, len(text) // 2)].encode(),
                ("application/json"),
            )
        elif encoding == "form" and isinstance(body, dict):
            data = urlencode(
                {
                    k: json.dumps(v) if not isinstance(v, str) else v
                    for k, v in body.items()
                },
                encoding="utf-8",
                errors="surrogatepass",
            ).encode("ascii")
            content_type = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(body, allow_nan=True).encode()
            content_type = "application/json"
        response = self.client.generic(method, path, data, content_type=content_type)
        return Sent(
            method,
            path,
            response.status_code,
            response.content,
            response.get("Content-Type", ""),
        )

    def _check(self, sent: Sent, url_name: str, signed_in: bool):
        label = f"{sent.method} {sent.path} -> {sent.status}"
        self.assertLess(sent.status, 500, f"{label}: {sent.body[:500]!r}")
        try:
            # Django routes on the decoded path, as the server sees it.
            resolve(unquote(sent.path.split("?")[0], errors="surrogateescape"))
        except Resolver404:
            return  # Django's own 404 for a path no view matches.
        # A refusal may say nothing (a bare 404), but whatever it says must be
        # JSON, which is all the app parses.
        if 400 <= sent.status < 500 and sent.body:
            self.assertTrue(
                sent.content_type.startswith("application/json"),
                f"{label}: a refusal the app can't parse ({sent.content_type})",
            )
            json.loads(sent.body)
        schema = CONTRACT_SCHEMAS.get((url_name, sent.method, sent.status, signed_in))
        if schema and 200 <= sent.status < 300:
            errors = schema_errors(api_validator(schema), json.loads(sent.body))
            self.assertEqual(
                errors, [], f"{label}: answer breaks the {schema} contract"
            )

    def _fuzz_route(self, target: Target, data):
        method = data.draw(st.sampled_from(target.methods), label="method")
        pk = None
        if target.ids:
            pk = data.draw(
                st.one_of(
                    st.sampled_from(target.ids(self.seed)),
                    st.sampled_from(NASTY_STRINGS),
                    st.text(min_size=1, max_size=30),
                ),
                label="id",
            )
        try:
            path = target.url(_quoted(pk) if pk is not None else None)
        except Exception:  # noqa: BLE001 - reverse() refuses some ids itself
            path = target.url("x").replace("/x/", "/" + _quoted(pk or "") + "/")
        if target.query or method == "GET":
            base = dict(target.query or {})
            if "person" in base:
                base["person"] = self.seed.person_a
            query = data.draw(
                st.one_of(
                    st.just(base),
                    mutated(base).filter(lambda q: isinstance(q, dict)),
                    st.dictionaries(
                        st.text(max_size=8), st.text(max_size=20), max_size=3
                    ),
                ),
                label="query",
            )
            if query:
                path += "?" + urlencode(
                    {str(k): str(v) for k, v in query.items()},
                    encoding="utf-8",
                    errors="surrogatepass",
                )
        body = None
        if target.bodies and method in target.bodies:
            body = data.draw(mutated(target.bodies[method](self.seed)), label="body")
        elif method in ("POST", "PUT", "PATCH"):
            body = data.draw(json_values, label="body")
        caller = data.draw(callers, label="caller")
        token = data.draw(junk_tokens, label="token") if caller == "junk" else ""
        encoding = data.draw(encodings, label="encoding")

        cache.clear()
        self._sign_in(caller, token)
        self._check(
            self._send(method, path, body, encoding),
            target.name,
            signed_in=caller in ("owner", "other"),
        )


def _make_test(target: Target):
    @fuzz
    @given(data=st.data())
    def test(self, data):
        self._fuzz_route(target, data)

    test.__name__ = f"test_{target.name.replace('-', '_')}"
    test.__doc__ = f"Fuzz {target.name} ({', '.join(target.methods)})."
    return test


for _target in TARGETS:
    _test = _make_test(_target)
    setattr(ApiFuzzTests, _test.__name__, _test)


class FuzzCoverageTests(SimpleTestCase):
    def test_every_route_is_fuzzed(self):
        """A new route fails here until it has a fuzz target."""
        self.assertEqual(
            sorted(MATRIX),
            sorted(t.name for t in TARGETS),
        )

    def test_profiles_are_reproducible(self):
        self.assertIn(PROFILE, ("pr", "nightly"))
        # The per-PR run must be the same run every time.
        self.assertEqual(FUZZ.derandomize, PROFILE == "pr")
