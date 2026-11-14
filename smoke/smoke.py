#!/usr/bin/env python3
"""The post-deploy smoke test: is a deployed API actually working?

It walks the path every user takes, against a real deployment:

  1. /health answers (the process is up).
  2. Sign in: with SMOKE_USERNAME / SMOKE_PASSWORD if set, otherwise by
     registering a throwaway account first. Until the GCIP migration, users
     live in SQLite on the instance, so production can't keep a standing
     smoke account; a new revision starts with none. For the same reason a
     throwaway account exists only on the instances it was registered on:
     when a request lands on another (sign-in refused, or a token's user
     "not found"), it's registered there too and the request retried, a
     few times at most. Auth that's really broken still fails.
  3. A Firestore-free read: the nearest airport to Heathrow is LHR (the
     in-memory reference data loaded).
  4. A Firestore round trip: create a trip, find it in the list, delete it,
     and see it gone. A missing index, a permission or a credentials
     problem shows up here.
  5. CORS: if SMOKE_WEB_ORIGIN is set, the API lets the web app call it.

It leaves no data behind: the trip is deleted even if a later check fails.
(A registered throwaway account stays, in SQLite, until the instance goes.)

Used three ways:
  - every PR, against the production image on a throwaway stack
    (`make smoke`, the Smoke Test job in CI),
  - by the release, against the new revision before it takes any traffic,
    and again against the live URL after,
  - hourly against production (.github/workflows/smoke.yml).

Configuration (environment):
  SMOKE_BASE_URL     the API's root, e.g. https://api.example.com (required)
  SMOKE_USERNAME     an existing account to sign in with (optional)
  SMOKE_PASSWORD     its password
  SMOKE_WEB_ORIGIN   the web app's origin, to check CORS (optional)
  SMOKE_TIMEOUT      seconds per request (default 20; a cold start is ~2 s)

Only the standard library, so it runs anywhere Python 3.10+ does.
Exit status: 0 when every check passed, 1 otherwise.
"""

from __future__ import annotations

import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field

# How many times one request is tried when the instance that answers doesn't
# have the throwaway account. Production runs at most 3 instances
# (infra/cloud_run.tf); each retry registers the account on whichever
# instance answers, so it spreads to them all within a few.
ATTEMPTS = 8


class SmokeFailure(Exception):
    """A check failed. The message says which, and what was seen."""


@dataclass
class Response:
    status: int
    headers: dict[str, str]
    body: bytes

    def json(self):
        try:
            return json.loads(self.body)
        except ValueError as e:
            raise SmokeFailure(f"expected JSON, got: {self.body[:200]!r}") from e


@dataclass
class Client:
    base_url: str
    timeout: float = 20.0
    token: str | None = None
    # The throwaway account's registration, once registered, to register it
    # again on an instance that doesn't have it. None for a standing account.
    account: dict | None = None
    # Sent with every request; the release sets nothing here, tests do.
    extra_headers: dict[str, str] = field(default_factory=dict)

    def request(self, method, path, body=None, headers=None) -> Response:
        return self.retry_without_account(
            lambda: self._send(method, path, body, headers), _user_not_found
        )

    def retry_without_account(self, send, missing) -> Response:
        """send(), retried while missing(response) says the instance that
        answered hasn't got the throwaway account, after registering it on
        another. A standing account (self.account None) is never retried.

        Every second retry registers twice, so the requests can't fall into
        step with a fixed rotation of instances (always registering on one
        that has the account, and retrying on one that hasn't).
        """
        response = send()
        for attempt in range(1, ATTEMPTS):
            if not (self.account and missing(response)):
                break
            self.register_here()
            if attempt % 2 == 0:
                self.register_here()
            response = send()
        return response

    def register_here(self):
        """Register the throwaway account on whichever instance answers.

        The username already taken there is fine: it's this account.
        """
        response = self._send(
            "POST", "/api/user/auth/register/", self.account, auth=False
        )
        if response.status == 201:
            return
        if response.status == 400 and "username" in _json_or_empty(response):
            return
        raise SmokeFailure(
            "registering the throwaway account: expected 201, "
            f"got {response.status}: {response.body[:300]!r}"
        )

    def _send(self, method, path, body=None, headers=None, auth=True) -> Response:
        url = self.base_url.rstrip("/") + path
        data = None
        all_headers = {"Accept": "application/json", **self.extra_headers}
        if body is not None:
            data = json.dumps(body).encode()
            all_headers["Content-Type"] = "application/json"
        if self.token and auth:
            all_headers["Authorization"] = f"Bearer {self.token}"
        all_headers.update(headers or {})
        req = urllib.request.Request(url, data=data, method=method, headers=all_headers)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                return Response(r.status, _lower(r.headers), r.read())
        except urllib.error.HTTPError as e:
            return Response(e.code, _lower(e.headers), e.read())
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            raise SmokeFailure(f"{method} {path}: no answer ({e})") from e


def _lower(headers) -> dict[str, str]:
    return {k.lower(): v for k, v in headers.items()}


def _json_or_empty(response: Response) -> dict:
    try:
        body = json.loads(response.body)
    except ValueError:
        return {}
    return body if isinstance(body, dict) else {}


def _user_not_found(response: Response) -> bool:
    """A valid token whose user isn't on the instance that answered."""
    return (
        response.status == 401
        and _json_or_empty(response).get("code") == "user_not_found"
    )


def expect(response: Response, status: int, what: str) -> Response:
    if response.status != status:
        raise SmokeFailure(
            f"{what}: expected {status}, got {response.status}: {response.body[:300]!r}"
        )
    return response


# Each check: (name, function(client, state)). They run in order and share
# state (the token, the trip id); the first failure stops the run.


def check_health(client, state):
    body = expect(client.request("GET", "/health"), 200, "GET /health").json()
    if body != {"status": "ok"}:
        raise SmokeFailure(f"/health answered {body!r}")


def check_sign_in(client, state):
    username = os.environ.get("SMOKE_USERNAME")
    password = os.environ.get("SMOKE_PASSWORD")
    if not username:
        # A throwaway account. The password is random, and doesn't resemble
        # the username (the similarity validator would refuse it).
        username = f"smoke-{secrets.token_hex(6)}"
        password = secrets.token_urlsafe(18)
        account = {
            "username": username,
            "email": f"{username}@example.com",
            "password": password,
            "password_confirm": password,
            "first_name": "Smoke",
            "last_name": "Test",
        }
        expect(
            client.request("POST", "/api/user/auth/register/", account),
            201,
            "registering a throwaway account",
        )
        client.account = account
    credentials = {"username": username, "password": password}
    # Refused (401) may mean the instance that answered hasn't the account.
    response = client.retry_without_account(
        lambda: client.request("POST", "/api/user/auth/token/", credentials),
        lambda r: r.status == 401,
    )
    tokens = expect(response, 200, "signing in").json()
    if not tokens.get("access"):
        raise SmokeFailure("signing in returned no access token")
    client.token = tokens["access"]


def check_reference_data(client, state):
    nearest = expect(
        client.request("GET", "/api/airports/nearest/?lat=51.47&lon=-0.45&count=1"),
        200,
        "the nearest airport",
    ).json()
    features = nearest.get("features") or []
    code = features[0]["properties"].get("iata_code") if features else None
    if code != "LHR":
        raise SmokeFailure(f"the nearest airport to Heathrow was {code!r}, not LHR")


def check_trip_round_trip(client, state):
    created = expect(
        client.request(
            "POST",
            "/api/trips/",
            {
                "name": f"Smoke test {time.strftime('%Y-%m-%d %H:%M:%S')}",
                "date": time.strftime("%Y-%m-%d"),
                "status": "DRAFT",
                "stops": [],
            },
        ),
        201,
        "creating a trip",
    ).json()
    trip_id = created.get("id")
    if not trip_id:
        raise SmokeFailure(f"the created trip has no id: {created!r}")
    state["trip_id"] = trip_id

    listed = expect(client.request("GET", "/api/trips/"), 200, "listing trips").json()
    if trip_id not in {t.get("id") for t in listed}:
        raise SmokeFailure("the new trip isn't in the trip list")

    expect(client.request("DELETE", f"/api/trips/{trip_id}/"), 204, "deleting the trip")
    state.pop("trip_id")
    expect(
        client.request("GET", f"/api/trips/{trip_id}/"),
        404,
        "reading the deleted trip",
    )


def check_cors(client, state):
    origin = os.environ.get("SMOKE_WEB_ORIGIN")
    if not origin:
        return "skipped (SMOKE_WEB_ORIGIN not set)"
    response = client.request(
        "OPTIONS",
        "/api/trips/",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )
    allowed = response.headers.get("access-control-allow-origin")
    if allowed != origin:
        raise SmokeFailure(
            f"the API doesn't allow the web app's origin {origin} (got {allowed!r})"
        )
    return None


CHECKS = [
    ("the API is up (/health)", check_health),
    ("sign in", check_sign_in),
    ("reference data (nearest airport)", check_reference_data),
    ("a trip round trip through Firestore", check_trip_round_trip),
    ("the web app may call the API (CORS)", check_cors),
]


def cleanup(client, state):
    """Delete the trip if a check failed between creating and deleting it."""
    trip_id = state.get("trip_id")
    if trip_id:
        response = client.request("DELETE", f"/api/trips/{trip_id}/")
        if response.status not in (204, 404):
            raise SmokeFailure(
                f"cleanup: deleting trip {trip_id} returned {response.status}"
            )


def run(client: Client, out=None) -> bool:
    out = out or sys.stdout
    state: dict = {}
    failure: SmokeFailure | None = None
    try:
        for name, check in CHECKS:
            started = time.monotonic()
            try:
                note = check(client, state)
            except SmokeFailure as e:
                failure = e
                print(f"FAIL  {name}: {e}", file=out)
                break
            ms = round((time.monotonic() - started) * 1000)
            print(f"ok    {name} ({note or f'{ms} ms'})", file=out)
    finally:
        try:
            cleanup(client, state)
        except SmokeFailure as e:
            # Reported, but never in place of the failure that caused it.
            print(f"FAIL  {e}", file=out)
            if failure is None:
                failure = e
    return failure is None


def main(argv=None) -> int:
    base_url = os.environ.get("SMOKE_BASE_URL", "")
    if not base_url:
        print("Set SMOKE_BASE_URL to the API's root URL.", file=sys.stderr)
        return 2
    client = Client(base_url, timeout=float(os.environ.get("SMOKE_TIMEOUT", "20")))
    print(f"Smoke test against {base_url}")
    ok = run(client)
    print("All smoke checks passed." if ok else "Smoke test FAILED.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
