#!/usr/bin/env python3
"""Signs up the user the ZAP scan acts as, and gives it data to attack.

    scripts/dast_seed.py http://localhost:8200/api/

Registers a user (POST user/auth/register/), signs in for a SimpleJWT access
token (POST user/auth/token/), then creates a person, a contact log and a trip
(which brings its stops and a leg) through the API, with the contracts'
request bodies. Without them every request ZAP makes to /people/{id}/ and the
like would stop at a 404 before reaching the code that matters.

Prints the access token on the first line, then one ROLE=ID line per record,
with the roles contracts/api/fixtures.json uses for its placeholders, and
ROLE@DELETE=ID lines for a second set that only DELETE requests use; pass
those to scripts/dast_openapi.py --id.

Standard library only.
"""

from __future__ import annotations

import json
import secrets
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INTERACTIONS = ROOT / "contracts" / "api" / "interactions"
FIXTURES = ROOT / "contracts" / "api" / "fixtures.json"


def contract_body(name: str) -> dict:
    with (INTERACTIONS / f"{name}.json").open(encoding="utf-8") as f:
        request = json.load(f)["request"]
    return request.get("json") or dict(request["multipart"]["fields"])


def call(base: str, method: str, path: str, body=None, token: str | None = None):
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(base + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read() or b"null")
    except urllib.error.HTTPError as err:
        sys.exit(f"{method} {path} answered {err.code}: {err.read()[:500].decode(errors='replace')}")


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    base = sys.argv[1].rstrip("/") + "/"
    with FIXTURES.open(encoding="utf-8") as f:
        placeholders = json.load(f)["placeholders"]
    placeholder_for = {role: value for value, role in placeholders.items()}

    # A fresh user per run; the password satisfies Django's validators.
    username = f"zap-{secrets.token_hex(4)}"
    password = f"Zap-{secrets.token_urlsafe(16)}"
    register = contract_body("auth.register") | {
        "username": username,
        "email": f"{username}@example.com",
        "password": password,
        "password_confirm": password,
    }
    call(base, "POST", "user/auth/register/", register)
    token = call(base, "POST", "user/auth/token/", {"username": username, "password": password})["access"]

    def create_records() -> dict[str, str]:
        """A person, a contact log with them and a trip to them, by role."""
        # The stub geocoder only knows a few cities (docker/e2e-stubs), and
        # Milwaukee, the contracts' city, isn't one of them.
        person_body = contract_body("people.create") | {"city": "Chicago", "state": "IL"}
        ids = {"person": call(base, "POST", "people/", person_body, token)["id"]}

        def with_ids(value):
            if isinstance(value, str):
                role = placeholders.get(value)
                return ids.get(role, value) if role else value
            if isinstance(value, list):
                return [with_ids(v) for v in value]
            if isinstance(value, dict):
                return {k: with_ids(v) for k, v in value.items()}
            return value

        log = call(base, "POST", "contact-logs/", with_ids(contract_body("contact_logs.create")), token)
        ids["contact_log"] = log["id"]
        trip = call(base, "POST", "trips/", with_ids(contract_body("trips.create")), token)
        ids["trip"] = trip["id"]
        stops = call(base, "GET", f"trips/{trip['id']}/stops/", token=token)
        for i, stop in enumerate(sorted(stops, key=lambda s: s["sequence_order"])):
            ids[f"trip.stop.{i}"] = stop["id"]
        legs = [leg for leg in call(base, "GET", "trips/legs/", token=token) if leg["trip"] == trip["id"]]
        for i, leg in enumerate(legs):
            ids[f"trip.leg.{i}"] = leg["id"]
        return {role: value for role, value in ids.items() if role in placeholder_for}

    ids = create_records()
    # ZAP's first DELETE would remove the records every other request uses,
    # and the rest of the scan would only see 404s. Its DELETEs get a second
    # set instead.
    for role, value in create_records().items():
        ids[f"{role}@DELETE"] = value

    print(token)
    for role, value in ids.items():
        print(f"{role}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
