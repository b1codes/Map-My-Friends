"""Consumer tests for the third parties the backend calls: Auth0 and Overpass.

Each feeds the provider's contract example (contracts/external/<provider>/)
through the real consuming code, and checks the request that code builds
against the contract. Whether the real providers still answer this way is
checked nightly by test_live_providers.
"""

from __future__ import annotations

import io
import json
import tempfile
import time
import urllib.parse
from pathlib import Path
from unittest import mock

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from django.conf import settings
from django.contrib.auth.models import User
from django.core.management import call_command
from django.test import SimpleTestCase, TestCase
from rest_framework.test import APIRequestFactory

from apps.stations.management.commands import fetch_stations
from apps.users.auth import Auth0JSONWebTokenAuthentication

from .support import (
    external_contract,
    external_contracts,
    load_json,
    normalize_whitespace,
    schema_errors,
)

SIGNING_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


class ExternalContractFileTests(SimpleTestCase):
    def test_every_example_matches_its_schema(self):
        self.assertGreater(len(external_contracts()), 0)
        for contract in external_contracts():
            with self.subTest(contract.id):
                errors = schema_errors(contract.validator(), contract.example())
                self.assertEqual(errors, [])

    def test_every_contract_says_whether_it_is_checked_live(self):
        for contract in external_contracts():
            with self.subTest(contract.id):
                self.assertIn(contract.spec["live"], (True, False))
                if not contract.spec["live"]:
                    self.assertTrue(contract.spec.get("live_note"))


class Auth0ConfigContractTests(SimpleTestCase):
    """Django and the Flutter app must point at the same Auth0 tenant."""

    def test_settings_match_the_shared_tenant(self):
        tenant = load_json("config/auth0.json")
        self.assertEqual(settings.AUTH0_DOMAIN, tenant["domain"])
        self.assertEqual(settings.AUTH0_AUDIENCE, tenant["audience"])

    def test_discovery_contract_is_for_the_shared_tenant(self):
        tenant = load_json("config/auth0.json")
        discovery = external_contract("auth0/openid_configuration")
        self.assertEqual(
            discovery.spec["response"]["expect"]["/issuer"],
            f"https://{tenant['domain']}/",
        )


class Auth0ConsumerContractTests(TestCase):
    """Auth0JSONWebTokenAuthentication against tokens and documents shaped
    like the contract's.

    The tenant's real keys can't sign a test token, so the JWKS served here is
    built from a throwaway key, but it has to satisfy the same JWKS schema
    the live check holds the tenant to.
    """

    def setUp(self):
        token_contract = external_contract("auth0/access_token")
        self.example = token_contract.example()
        self.kid = self.example["header"]["kid"]
        public_jwk = jwt.algorithms.RSAAlgorithm.to_jwk(
            SIGNING_KEY.public_key(), as_dict=True
        )
        self.jwks = {
            "keys": [{**public_jwk, "kid": self.kid, "use": "sig", "alg": "RS256"}]
        }
        jwks_contract = external_contract("auth0/jwks")
        self.assertEqual(schema_errors(jwks_contract.validator(), self.jwks), [])

        self.fetched_urls = []

        def fetch_data(client):
            self.fetched_urls.append(client.uri)
            return self.jwks

        patcher = mock.patch("jwt.PyJWKClient.fetch_data", fetch_data)
        patcher.start()
        self.addCleanup(patcher.stop)

    def _token(self, **claim_overrides):
        now = int(time.time())
        claims = {**self.example["claims"], "iat": now, "exp": now + 300}
        claims.update(claim_overrides)
        claims = {k: v for k, v in claims.items() if v is not None}
        token = jwt.encode(
            claims, SIGNING_KEY, algorithm="RS256", headers={"kid": self.kid}
        )
        decoded = {"header": jwt.get_unverified_header(token), "claims": claims}
        contract = external_contract("auth0/access_token")
        self.assertEqual(schema_errors(contract.validator(), decoded), [])
        return token

    def _authenticate(self, token):
        request = APIRequestFactory().get("/", HTTP_AUTHORIZATION=f"Bearer {token}")
        return Auth0JSONWebTokenAuthentication().authenticate(request)

    def test_contract_token_authenticates_and_names_the_user_from_sub(self):
        user, _ = self._authenticate(
            self._token(email="grace@example.com", email_verified=True)
        )
        self.assertEqual(user.username, "google-oauth2_104807611830372981423")
        self.assertEqual(user.email, "grace@example.com")

    def test_keys_come_from_the_contract_jwks_url(self):
        self._authenticate(self._token(email="grace@example.com"))
        self.assertEqual(
            self.fetched_urls, [external_contract("auth0/jwks").spec["request"]["url"]]
        )

    def test_the_userinfo_audience_alongside_the_api_audience_is_accepted(self):
        # With the openid scope Auth0 issues aud as a list; Django must find
        # its own audience in it rather than require an exact string.
        self.assertIsInstance(self.example["claims"]["aud"], list)
        user, _ = self._authenticate(self._token(email="grace@example.com"))
        self.assertIsInstance(user, User)

    def test_missing_email_is_filled_from_the_contract_userinfo(self):
        userinfo = external_contract("auth0/userinfo")
        response = mock.Mock(status_code=200)
        response.json.return_value = userinfo.example()
        with mock.patch(
            "apps.users.auth.requests.get", return_value=response
        ) as get_userinfo:
            user, _ = self._authenticate(self._token())

        self.assertEqual(
            get_userinfo.call_args.args[0], userinfo.spec["request"]["url"]
        )
        self.assertEqual(user.email, userinfo.example()["email"])
        self.assertEqual(user.first_name, userinfo.example()["given_name"])
        self.assertEqual(user.last_name, userinfo.example()["family_name"])


class OverpassConsumerContractTests(SimpleTestCase):
    def setUp(self):
        self.contract = external_contract("overpass/stations")
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.output = Path(tmp.name) / "stations_export.json"
        output = mock.patch.object(fetch_stations, "OUTPUT_PATH", self.output)
        output.start()
        self.addCleanup(output.stop)
        sleep = mock.patch.object(fetch_stations.time, "sleep")
        sleep.start()
        self.addCleanup(sleep.stop)

        self.requests = []

        def urlopen(request, timeout):
            self.requests.append(request)
            body = json.dumps(self.contract.example()).encode("utf-8")
            return io.BytesIO(body)

        with mock.patch.object(
            fetch_stations.urllib.request, "urlopen", side_effect=urlopen
        ):
            call_command("fetch_stations", "--states", "US-RI", stdout=io.StringIO())
        self.rows = json.loads(self.output.read_text(encoding="utf-8"))

    def test_request_matches_the_contract(self):
        expected = self.contract.spec["request"]
        (request,) = self.requests
        self.assertEqual(request.get_method(), expected["method"])
        self.assertEqual(request.full_url, expected["url"])
        for header, value in expected["headers"].items():
            self.assertEqual(request.get_header(header.capitalize()), value)
        form = urllib.parse.parse_qs(request.data.decode())
        self.assertEqual(set(form), set(expected["form"]))
        self.assertEqual(
            normalize_whitespace(form["data"][0]),
            normalize_whitespace(expected["form"]["data"]),
        )

    def test_named_nodes_become_stations_and_unnamed_ones_are_skipped(self):
        named = [
            e
            for e in self.contract.example()["elements"]
            if e.get("tags", {}).get("name")
        ]
        self.assertEqual(
            sorted(row["osm_id"] for row in self.rows), sorted(e["id"] for e in named)
        )

    def test_tags_drive_the_station_fields(self):
        providence = next(row for row in self.rows if row["name"] == "Providence")
        self.assertEqual(providence["station_type"], "major_station")
        self.assertEqual(providence["country"], "USA")
        self.assertAlmostEqual(providence["lat"], 41.8292289)
        self.assertAlmostEqual(providence["lon"], -71.4132485)
