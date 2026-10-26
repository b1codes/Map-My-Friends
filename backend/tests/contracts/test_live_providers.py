"""Provider verification against the real third parties.

Skipped unless CONTRACT_LIVE=1: these hit the public internet, so they run
nightly (.github/workflows/contracts-live.yml) rather than on every PR, where
a flaky upstream would block unrelated work. Each contract marked "live" is
requested exactly as written and its response must satisfy the same schema
the consumer tests are written against.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from unittest import SkipTest, skipUnless

from django.test import SimpleTestCase

from .support import external_contracts, resolve_pointer, schema_errors

LIVE = os.environ.get("CONTRACT_LIVE") == "1"
# Overpass and the OSRM demo server are shared public services that shed load
# with 429/502/503/504; those are retried, anything else fails at once.
RETRYABLE = {429, 502, 503, 504}
ATTEMPTS = 4


def _fetch(request_spec):
    url = request_spec["url"]
    if request_spec.get("query"):
        url += "?" + urllib.parse.urlencode(request_spec["query"])
    data = None
    if request_spec.get("form"):
        data = urllib.parse.urlencode(request_spec["form"]).encode()
    request = urllib.request.Request(
        url,
        data=data,
        method=request_spec["method"],
        headers={
            "User-Agent": "map-my-friends-contract-check/1.0 (+https://github.com/b1codes)",
            "Accept": "application/json",
            **request_spec.get("headers", {}),
        },
    )
    for attempt in range(ATTEMPTS):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as exc:
            if exc.code not in RETRYABLE or attempt == ATTEMPTS - 1:
                return exc.code, None
        except (urllib.error.URLError, TimeoutError):
            if attempt == ATTEMPTS - 1:
                raise
        time.sleep(10 * 2**attempt)
    raise AssertionError("unreachable")


@skipUnless(LIVE, "set CONTRACT_LIVE=1 to check the real third-party services")
class LiveProviderContractTests(SimpleTestCase):
    def verify(self, contract):
        if not contract.spec["live"]:
            raise SkipTest(contract.spec["live_note"])
        status, body = _fetch(contract.spec["request"])
        expected = contract.spec["response"]
        self.assertEqual(status, expected["status"], contract.id)
        self.assertEqual(schema_errors(contract.validator(), body), [], contract.id)
        for pointer, value in expected.get("expect", {}).items():
            with self.subTest(expect=pointer):
                self.assertEqual(resolve_pointer(body, pointer), value)


def _live_test(contract):
    def test(self):
        self.verify(contract)

    test.__doc__ = f"{contract.id}: {contract.spec['description']}"
    return test


for _contract in external_contracts():
    if "request" in _contract.spec:
        setattr(
            LiveProviderContractTests,
            f"test_{_contract.provider}_{_contract.name}",
            _live_test(_contract),
        )
