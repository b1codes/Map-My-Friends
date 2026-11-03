import logging
import sys

import jwt
import requests
from django.conf import settings
from django.contrib.auth.models import User
from django.utils.translation import gettext_lazy as _
from jwt import PyJWKClient
from rest_framework import authentication, exceptions

logger = logging.getLogger(__name__)

# Determine if we are running unit tests
TESTING = (
    "test" in sys.argv
    or "test_coverage" in sys.argv
    or getattr(settings, "TESTING", False)
)


class Auth0JSONWebTokenAuthentication(authentication.BaseAuthentication):
    """
    Custom DRF authentication class for Auth0 JWT tokens.
    Attempts to decode and verify JWTs using Auth0 JWKS.
    Supports a mock token fallback for testing and local development (DEBUG mode).
    """

    def authenticate(self, request):
        auth_header = authentication.get_authorization_header(request).split()
        if not auth_header:
            return None

        if len(auth_header) == 1:
            msg = _("Invalid Authorization header. No credentials provided.")
            raise exceptions.AuthenticationFailed(msg)
        if len(auth_header) > 2:
            msg = _(
                "Invalid Authorization header. Credentials string should not contain spaces."
            )
            raise exceptions.AuthenticationFailed(msg)

        auth_type = auth_header[0].decode("utf-8").lower()
        if auth_type != "bearer":
            return None

        token = auth_header[1].decode("utf-8")
        return self.authenticate_credentials(request, token)

    def authenticate_header(self, request):
        return "Bearer"

    def authenticate_credentials(self, request, token):
        # 1. Handle Mock Tokens in DEBUG or TESTING environments
        if (settings.DEBUG or TESTING) and token.startswith("mock_auth0_jwt_token_"):
            parts = token.split("_")
            # Format: mock_auth0_jwt_token_{username}_{timestamp}
            username = parts[4] if len(parts) >= 5 else "mock_auth0_user"

            email = f"{username}@example.com"
            user, _created = User.objects.get_or_create(
                username=username,
                defaults={
                    "email": email,
                    "first_name": username.capitalize(),
                    "last_name": "Mock",
                },
            )
            return (user, token)

        # 2. Extract and decode claims *without verification* first to inspect issuer
        try:
            unverified_payload = jwt.decode(token, options={"verify_signature": False})
        except Exception:  # noqa: BLE001 - any parse failure means "not our token"
            # If it cannot be parsed as a JWT at all, return None so other backends (e.g. SimpleJWT) can try
            return None

        auth0_domain = getattr(settings, "AUTH0_DOMAIN", "map-my-friends.us.auth0.com")
        auth0_audience = getattr(
            settings, "AUTH0_AUDIENCE", "https://mapmyfriends.com/api"
        )
        expected_issuer = f"https://{auth0_domain}/"

        # If the issuer is NOT our Auth0 domain, this is likely a SimpleJWT token
        if unverified_payload.get("iss") != expected_issuer:
            return None

        # 3. Perform cryptographic verification using Auth0 JWKS
        try:
            jwks_url = f"https://{auth0_domain}/.well-known/jwks.json"
            jwk_client = PyJWKClient(jwks_url)
            signing_key = jwk_client.get_signing_key_from_jwt(token)
            payload = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                audience=auth0_audience,
                issuer=expected_issuer,
            )
        except jwt.ExpiredSignatureError as e:
            raise exceptions.AuthenticationFailed(_("Token has expired.")) from e
        except jwt.InvalidTokenError as e:
            raise exceptions.AuthenticationFailed(
                _("Invalid token signature or claims: ") + str(e)
            ) from e
        except (
            Exception
        ) as e:  # deliberate catch-all so auth never leaks an internal error
            raise exceptions.AuthenticationFailed(
                _("Authentication failed: ") + str(e)
            ) from e

        sub = payload.get("sub")
        if not sub:
            raise exceptions.AuthenticationFailed(_("Missing sub claim in token."))

        # Convert sub to a valid Django username (e.g. auth0_123456 instead of auth0|123456)
        username = sub.replace("|", "_")

        try:
            user = User.objects.get(username=username)
        except User.DoesNotExist:
            # Create a new user automatically
            email = payload.get("email")
            first_name = payload.get("given_name", "")
            last_name = payload.get("family_name", "")

            # If profile info is missing from claims, fetch from /userinfo endpoint
            if not email:
                try:
                    userinfo_url = f"https://{auth0_domain}/userinfo"
                    response = requests.get(
                        userinfo_url,
                        headers={"Authorization": f"Bearer {token}"},
                        timeout=5,
                    )
                    if response.status_code == 200:
                        user_info = response.json()
                        email = user_info.get("email")
                        first_name = user_info.get(
                            "given_name", user_info.get("nickname", "")
                        )
                        last_name = user_info.get("family_name", "")
                except Exception:
                    # Not fatal: the email falls back to a temporary address
                    # below. Logged so a failing userinfo endpoint is still
                    # diagnosable rather than silent.
                    logger.warning("Auth0 userinfo lookup failed", exc_info=True)

            if not email:
                email = f"{username}@temporary.auth0.com"

            # Check if user with this email already exists to prevent duplicate emails
            # Only associate if email is verified in Auth0 to prevent spoofing
            email_verified = payload.get("email_verified", False)
            existing_user = User.objects.filter(email=email).first()
            if existing_user and email_verified:
                user = existing_user
            else:
                user = User.objects.create_user(
                    username=username,
                    email=email,
                    first_name=first_name,
                    last_name=last_name,
                )

        return (user, token)
