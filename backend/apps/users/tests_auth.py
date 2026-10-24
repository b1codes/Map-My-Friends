"""Tests for the Auth0 DRF authentication backend.

Real RS256 tokens are signed with a throwaway keypair and only the JWKS fetch
is stubbed, so PyJWT's actual signature, expiry, audience and issuer checks
run. The /userinfo call is the only other external dependency mocked.
"""

import time
from unittest.mock import MagicMock, patch

import jwt
import requests
from cryptography.hazmat.primitives.asymmetric import rsa
from django.contrib.auth.models import User
from django.test import TestCase, override_settings
from jwt import PyJWKClient
from rest_framework import exceptions
from rest_framework.test import APIRequestFactory, APITestCase

from apps.common.testing import FirestoreTestMixin
from apps.users.auth import Auth0JSONWebTokenAuthentication

AUTH0_DOMAIN = "tenant.test.auth0.com"
AUTH0_AUDIENCE = "https://api.test.example/"
ISSUER = f"https://{AUTH0_DOMAIN}/"
KID = "test-key-1"

# One keypair for the whole module: RSA generation is the slow part.
SIGNING_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
OTHER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)

JWKS = {
    "keys": [
        {
            **jwt.algorithms.RSAAlgorithm.to_jwk(
                SIGNING_KEY.public_key(), as_dict=True
            ),
            "kid": KID,
            "use": "sig",
            "alg": "RS256",
        }
    ]
}


def auth0_token(key=SIGNING_KEY, kid=KID, **overrides):
    """Sign an Auth0-shaped access token; pass a claim as None to drop it."""
    now = int(time.time())
    claims = {
        "iss": ISSUER,
        "aud": AUTH0_AUDIENCE,
        "sub": "auth0|abc123",
        "iat": now,
        "exp": now + 300,
    }
    claims.update(overrides)
    claims = {k: v for k, v in claims.items() if v is not None}
    return jwt.encode(claims, key, algorithm="RS256", headers={"kid": kid})


def request_with(authorization):
    return APIRequestFactory().get("/", HTTP_AUTHORIZATION=authorization)


class AuthorizationHeaderTests(TestCase):
    def setUp(self):
        self.backend = Auth0JSONWebTokenAuthentication()

    def test_missing_header_defers_to_other_backends(self):
        self.assertIsNone(self.backend.authenticate(APIRequestFactory().get("/")))

    def test_scheme_without_credentials_is_rejected(self):
        with self.assertRaisesMessage(
            exceptions.AuthenticationFailed, "No credentials provided"
        ):
            self.backend.authenticate(request_with("Bearer"))

    def test_credentials_containing_spaces_are_rejected(self):
        with self.assertRaisesMessage(
            exceptions.AuthenticationFailed, "should not contain spaces"
        ):
            self.backend.authenticate(request_with("Bearer abc def"))

    def test_non_bearer_scheme_defers_to_other_backends(self):
        self.assertIsNone(self.backend.authenticate(request_with("Basic dXNlcjpwdw==")))

    def test_scheme_is_case_insensitive(self):
        user, _token = self.backend.authenticate(
            request_with("bearer mock_auth0_jwt_token_casey_1")
        )
        self.assertEqual(user.username, "casey")

    def test_unparseable_token_defers_to_other_backends(self):
        self.assertIsNone(self.backend.authenticate(request_with("Bearer not-a-jwt")))

    def test_token_from_another_issuer_defers_to_other_backends(self):
        # SimpleJWT tokens carry no Auth0 issuer; they must fall through so
        # JWTAuthentication can verify them.
        token = auth0_token(iss="https://someone-else.example/")
        with override_settings(AUTH0_DOMAIN=AUTH0_DOMAIN):
            self.assertIsNone(
                self.backend.authenticate(request_with(f"Bearer {token}"))
            )

    def test_challenge_header_advertises_bearer(self):
        self.assertEqual(self.backend.authenticate_header(None), "Bearer")


class MockTokenTests(TestCase):
    def setUp(self):
        self.backend = Auth0JSONWebTokenAuthentication()

    def test_mock_token_creates_user_from_embedded_username(self):
        token = "mock_auth0_jwt_token_casey_1700000000000"
        user, returned_token = self.backend.authenticate(
            request_with(f"Bearer {token}")
        )

        self.assertEqual(returned_token, token)
        self.assertEqual(user.username, "casey")
        self.assertEqual(user.email, "casey@example.com")
        self.assertEqual(user.first_name, "Casey")
        self.assertEqual(user.last_name, "Mock")

    def test_mock_token_reuses_existing_user(self):
        existing = User.objects.create_user(
            username="casey", email="real@example.com", first_name="Real"
        )
        user, _token = self.backend.authenticate(
            request_with("Bearer mock_auth0_jwt_token_casey_1")
        )

        self.assertEqual(user.pk, existing.pk)
        # get_or_create defaults must not overwrite an existing account.
        user.refresh_from_db()
        self.assertEqual(user.email, "real@example.com")
        self.assertEqual(user.first_name, "Real")
        self.assertEqual(User.objects.count(), 1)

    @override_settings(DEBUG=False)
    @patch("apps.users.auth.TESTING", False)
    def test_mock_token_is_ignored_outside_debug_and_tests(self):
        # In production a mock token is just an unparseable bearer token: it
        # must not mint a user, and is left for the next backend to reject.
        result = self.backend.authenticate(
            request_with("Bearer mock_auth0_jwt_token_intruder_1")
        )

        self.assertIsNone(result)
        self.assertFalse(User.objects.filter(username="intruder").exists())


@override_settings(AUTH0_DOMAIN=AUTH0_DOMAIN, AUTH0_AUDIENCE=AUTH0_AUDIENCE)
class Auth0VerificationTests(TestCase):
    def setUp(self):
        self.backend = Auth0JSONWebTokenAuthentication()
        fetch = patch.object(
            PyJWKClient, "fetch_data", autospec=True, return_value=JWKS
        )
        self.fetch_data = fetch.start()
        self.addCleanup(fetch.stop)
        userinfo = patch("apps.users.auth.requests.get")
        self.userinfo = userinfo.start()
        self.addCleanup(userinfo.stop)

    def authenticate(self, token):
        return self.backend.authenticate(request_with(f"Bearer {token}"))

    def test_keys_are_fetched_from_the_tenant_jwks_endpoint(self):
        self.authenticate(auth0_token(email="ada@example.com"))

        client = self.fetch_data.call_args.args[0]
        self.assertEqual(client.uri, f"https://{AUTH0_DOMAIN}/.well-known/jwks.json")

    def test_valid_token_resolves_existing_user_by_sub(self):
        existing = User.objects.create_user(username="auth0_abc123")
        token = auth0_token()

        user, returned_token = self.authenticate(token)

        self.assertEqual(user.pk, existing.pk)
        self.assertEqual(returned_token, token)
        self.userinfo.assert_not_called()

    def test_first_login_creates_user_from_token_claims(self):
        user, _token = self.authenticate(
            auth0_token(
                sub="google-oauth2|987",
                email="ada@example.com",
                given_name="Ada",
                family_name="Lovelace",
            )
        )

        # "|" is not a valid username character, so it is swapped for "_".
        self.assertEqual(user.username, "google-oauth2_987")
        self.assertEqual(user.email, "ada@example.com")
        self.assertEqual(user.first_name, "Ada")
        self.assertEqual(user.last_name, "Lovelace")
        self.assertFalse(user.has_usable_password())
        self.userinfo.assert_not_called()

    def test_second_login_does_not_create_another_user(self):
        token = auth0_token(email="ada@example.com")
        first, _ = self.authenticate(token)
        second, _ = self.authenticate(token)

        self.assertEqual(first.pk, second.pk)
        self.assertEqual(User.objects.count(), 1)

    def test_expired_token_is_rejected(self):
        now = int(time.time())
        token = auth0_token(iat=now - 600, exp=now - 300)

        with self.assertRaisesMessage(
            exceptions.AuthenticationFailed, "Token has expired."
        ):
            self.authenticate(token)

    def test_wrong_audience_is_rejected(self):
        token = auth0_token(aud="https://some-other-api.example/")

        with self.assertRaisesMessage(
            exceptions.AuthenticationFailed, "Invalid token signature or claims"
        ):
            self.authenticate(token)

    def test_forged_signature_is_rejected(self):
        # Right kid, wrong private key: only real signature checking catches it.
        token = auth0_token(key=OTHER_KEY)

        with self.assertRaisesMessage(
            exceptions.AuthenticationFailed, "Invalid token signature or claims"
        ):
            self.authenticate(token)
        self.assertEqual(User.objects.count(), 0)

    def test_unknown_signing_key_fails_authentication(self):
        token = auth0_token(kid="rotated-away")

        with self.assertRaisesMessage(
            exceptions.AuthenticationFailed, "Authentication failed: "
        ):
            self.authenticate(token)

    def test_jwks_outage_fails_authentication(self):
        self.fetch_data.side_effect = jwt.PyJWKClientConnectionError("timed out")

        with self.assertRaisesMessage(
            exceptions.AuthenticationFailed, "Authentication failed: timed out"
        ):
            self.authenticate(auth0_token())

    def test_missing_sub_is_rejected(self):
        with self.assertRaisesMessage(
            exceptions.AuthenticationFailed, "Missing sub claim in token."
        ):
            self.authenticate(auth0_token(sub=None))
        self.assertEqual(User.objects.count(), 0)

    def test_missing_email_is_fetched_from_userinfo(self):
        self.userinfo.return_value = MagicMock(
            status_code=200,
            json=MagicMock(
                return_value={
                    "email": "grace@example.com",
                    "given_name": "Grace",
                    "family_name": "Hopper",
                }
            ),
        )
        token = auth0_token()

        user, _token = self.authenticate(token)

        self.userinfo.assert_called_once_with(
            f"https://{AUTH0_DOMAIN}/userinfo",
            headers={"Authorization": f"Bearer {token}"},
            timeout=5,
        )
        self.assertEqual(user.email, "grace@example.com")
        self.assertEqual(user.first_name, "Grace")
        self.assertEqual(user.last_name, "Hopper")

    def test_userinfo_nickname_stands_in_for_missing_given_name(self):
        self.userinfo.return_value = MagicMock(
            status_code=200,
            json=MagicMock(
                return_value={"email": "grace@example.com", "nickname": "amazing"}
            ),
        )

        user, _token = self.authenticate(auth0_token())

        self.assertEqual(user.first_name, "amazing")
        self.assertEqual(user.last_name, "")

    def test_userinfo_error_status_falls_back_to_temporary_email(self):
        self.userinfo.return_value = MagicMock(status_code=401)

        user, _token = self.authenticate(auth0_token(given_name="Ada"))

        self.assertEqual(user.email, "auth0_abc123@temporary.auth0.com")
        # Claims already read from the token survive a failed lookup.
        self.assertEqual(user.first_name, "Ada")

    def test_userinfo_network_failure_is_logged_and_not_fatal(self):
        self.userinfo.side_effect = requests.ConnectionError("unreachable")

        with self.assertLogs("apps.users.auth", level="WARNING") as logs:
            user, _token = self.authenticate(auth0_token())

        self.assertIn("Auth0 userinfo lookup failed", logs.output[0])
        self.assertEqual(user.email, "auth0_abc123@temporary.auth0.com")

    def test_verified_email_links_to_existing_account(self):
        existing = User.objects.create_user(
            username="ada", email="ada@example.com", password="pw12345!"
        )

        user, _token = self.authenticate(
            auth0_token(email="ada@example.com", email_verified=True)
        )

        self.assertEqual(user.pk, existing.pk)
        self.assertFalse(User.objects.filter(username="auth0_abc123").exists())

    def test_unverified_email_does_not_take_over_existing_account(self):
        # Anyone can claim an address at an IdP; without verification the
        # login must not be handed someone else's account.
        existing = User.objects.create_user(
            username="ada", email="ada@example.com", password="pw12345!"
        )

        user, _token = self.authenticate(auth0_token(email="ada@example.com"))

        self.assertNotEqual(user.pk, existing.pk)
        self.assertEqual(user.username, "auth0_abc123")


@override_settings(AUTH0_DOMAIN=AUTH0_DOMAIN, AUTH0_AUDIENCE=AUTH0_AUDIENCE)
@patch.object(PyJWKClient, "fetch_data", return_value=JWKS)
class Auth0EndpointTests(FirestoreTestMixin, APITestCase):
    """The backend wired into DRF's DEFAULT_AUTHENTICATION_CLASSES."""

    collections_to_purge = ["user_profiles"]

    def test_valid_auth0_token_reaches_profile(self, _fetch):
        token = auth0_token(email="ada@example.com")
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")

        response = self.client.get("/api/user/profile/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["username"], "auth0_abc123")
        self.assertEqual(response.data["email"], "ada@example.com")

    def test_expired_auth0_token_is_401_with_reason(self, _fetch):
        now = int(time.time())
        token = auth0_token(iat=now - 600, exp=now - 300)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")

        response = self.client.get("/api/user/profile/")

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.data["detail"], "Token has expired.")
        self.assertEqual(response["WWW-Authenticate"], "Bearer")

    def test_malformed_header_is_401(self, _fetch):
        self.client.credentials(HTTP_AUTHORIZATION="Bearer")

        response = self.client.get("/api/user/profile/")

        self.assertEqual(response.status_code, 401)
        self.assertIn("No credentials provided", response.data["detail"])
