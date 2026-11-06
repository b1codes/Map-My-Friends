"""The settings a deployment gets, as opposed to the ones the test run uses.

The test run, the dev stack and the E2E stack all set DJANGO_DEBUG=True, so the
production branches of config/settings.py never ran under test. These tests
load the settings module afresh under a chosen environment, the way a server
process would, and check what it ends up with. One also runs Django's own
deployment checklist (`check --deploy`) in a separate process, since that
needs Django set up with the production settings rather than the test ones.
"""

import importlib.util
import os
import secrets
import subprocess
import sys
from pathlib import Path
from unittest import mock

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.test import SimpleTestCase, override_settings
from rest_framework.test import APIRequestFactory
from rest_framework.throttling import AnonRateThrottle

import config.settings as settings_module

BACKEND_DIR = Path(settings.BASE_DIR)

# Variables a deployment sets. They're removed before each load so the
# container's own values (DJANGO_DEBUG=True in docker-compose.yml) don't leak
# into a test about what happens without them.
DEPLOY_VARS = (
    "DJANGO_DEBUG",
    "DJANGO_SECRET_KEY",
    "DJANGO_NUM_PROXIES",
    "ALLOWED_HOSTS",
    "CORS_ALLOWED_ORIGINS",
    "CSRF_TRUSTED_ORIGINS",
    "SECURE_SSL_REDIRECT",
)

# A key that isn't the committed default, as a real deployment would set.
PRODUCTION_KEY = secrets.token_urlsafe(50)

PRODUCTION_ENV = {
    "DJANGO_DEBUG": "False",
    "DJANGO_SECRET_KEY": PRODUCTION_KEY,
    "DJANGO_NUM_PROXIES": "1",
    "ALLOWED_HOSTS": "api.example.com",
    "CORS_ALLOWED_ORIGINS": "https://app.example.com",
    "CSRF_TRUSTED_ORIGINS": "https://app.example.com",
    "SECURE_SSL_REDIRECT": "True",
}


def deploy_environ(**env):
    """os.environ without any deployment variable, plus the given ones."""
    base = {k: v for k, v in os.environ.items() if k not in DEPLOY_VARS}
    return {**base, **env}


def load_settings(**env):
    """Execute config/settings.py as a new module under the given environment.

    The module Django already imported is left alone; this is a second copy,
    so a test can read what a server started with `env` would get.
    """
    spec = importlib.util.spec_from_file_location(
        "isolated_settings", settings_module.__file__
    )
    module = importlib.util.module_from_spec(spec)
    with mock.patch.dict(os.environ, deploy_environ(**env), clear=True):
        spec.loader.exec_module(module)
    return module


class DebugDefaultTests(SimpleTestCase):
    def test_debug_is_off_unless_the_environment_turns_it_on(self):
        # DEBUG on means debug pages with settings and stack traces, media
        # served by Django, and the mock Auth0 tokens that sign in as anyone
        # (apps/users/auth.py). A server whose env forgot DJANGO_DEBUG must
        # get none of that.
        loaded = load_settings(DJANGO_SECRET_KEY=PRODUCTION_KEY)

        self.assertFalse(loaded.DEBUG)

    def test_debug_is_on_only_when_asked_for(self):
        self.assertTrue(load_settings(DJANGO_DEBUG="True").DEBUG)
        self.assertTrue(load_settings(DJANGO_DEBUG="true").DEBUG)

    def test_production_refuses_the_committed_secret_key(self):
        # SECRET_KEY signs the SimpleJWT tokens. The default is in the public
        # repository, so with it anyone could mint an access token for any
        # user. Starting must fail rather than run with it.
        with self.assertRaisesMessage(ImproperlyConfigured, "DJANGO_SECRET_KEY"):
            load_settings(DJANGO_DEBUG="False")

    def test_development_may_use_the_committed_secret_key(self):
        loaded = load_settings(DJANGO_DEBUG="True")

        self.assertTrue(loaded.SECRET_KEY.startswith("django-insecure-"))

    def test_production_uses_the_key_it_is_given(self):
        self.assertEqual(load_settings(**PRODUCTION_ENV).SECRET_KEY, PRODUCTION_KEY)


class ProductionSettingsTests(SimpleTestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.prod = load_settings(**PRODUCTION_ENV)

    def test_cors_allows_only_the_configured_origins(self):
        self.assertFalse(getattr(self.prod, "CORS_ALLOW_ALL_ORIGINS", False))
        self.assertEqual(self.prod.CORS_ALLOWED_ORIGINS, ["https://app.example.com"])

    def test_an_unset_cors_list_allows_no_origin(self):
        # "".split(",") is [""], which django-cors-headers rejects as an
        # origin; unset must mean an empty allow-list.
        loaded = load_settings(
            **{**PRODUCTION_ENV, "CORS_ALLOWED_ORIGINS": ""},
        )

        self.assertEqual(loaded.CORS_ALLOWED_ORIGINS, [])

    def test_hosts_are_only_the_configured_ones(self):
        self.assertEqual(self.prod.ALLOWED_HOSTS, ["api.example.com"])

    def test_cookies_are_https_only(self):
        self.assertTrue(self.prod.SESSION_COOKIE_SECURE)
        self.assertTrue(self.prod.CSRF_COOKIE_SECURE)

    def test_hsts_and_framing_headers_are_on(self):
        self.assertGreaterEqual(self.prod.SECURE_HSTS_SECONDS, 31536000)
        self.assertTrue(self.prod.SECURE_HSTS_INCLUDE_SUBDOMAINS)
        self.assertTrue(self.prod.SECURE_CONTENT_TYPE_NOSNIFF)
        self.assertEqual(self.prod.X_FRAME_OPTIONS, "DENY")

    def test_https_is_recognised_behind_the_proxy(self):
        # nginx terminates TLS and sets X-Forwarded-Proto (nginx.conf.example).
        # Without this, SECURE_SSL_REDIRECT would redirect every proxied
        # request forever, and request.is_secure() would always be False.
        self.assertTrue(self.prod.SECURE_SSL_REDIRECT)
        self.assertEqual(
            self.prod.SECURE_PROXY_SSL_HEADER, ("HTTP_X_FORWARDED_PROTO", "https")
        )

    def test_development_does_not_trust_a_forwarded_proto(self):
        # With no proxy in front, a client could send the header itself.
        loaded = load_settings(DJANGO_DEBUG="True")

        self.assertIsNone(getattr(loaded, "SECURE_PROXY_SSL_HEADER", None))
        self.assertTrue(loaded.CORS_ALLOW_ALL_ORIGINS)


class DeployChecklistTests(SimpleTestCase):
    def test_production_settings_pass_djangos_deploy_checks(self):
        """`manage.py check --deploy` with the production environment.

        Any warning fails: each one is a security setting Django's checklist
        says a deployment needs (HSTS, secure cookies, SSL redirect, a strong
        SECRET_KEY, DEBUG off, ...).
        """
        result = subprocess.run(
            [
                sys.executable,
                "manage.py",
                "check",
                "--deploy",
                "--fail-level",
                "WARNING",
            ],
            cwd=BACKEND_DIR,
            env=deploy_environ(**PRODUCTION_ENV),
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )

        self.assertEqual(
            result.returncode, 0, msg=f"\n{result.stdout}\n{result.stderr}"
        )


class ThrottleClientIdentityTests(SimpleTestCase):
    """Anonymous throttles count per client; the client must not pick its id.

    DRF keys an anonymous client by the whole X-Forwarded-For header unless
    NUM_PROXIES is set. The header is the client's to write, so sending a
    different value on each request dodged every anonymous limit: login
    guessing, sign-ups and password-reset requests alike.
    """

    def ident(self, **meta):
        request = APIRequestFactory().get("/", **meta)
        return AnonRateThrottle().get_ident(request)

    def test_a_spoofed_forwarded_for_does_not_change_the_client(self):
        first = self.ident(REMOTE_ADDR="203.0.113.7", HTTP_X_FORWARDED_FOR="1.1.1.1")
        second = self.ident(REMOTE_ADDR="203.0.113.7", HTTP_X_FORWARDED_FOR="2.2.2.2")

        self.assertEqual(first, second)
        self.assertEqual(first, "203.0.113.7")

    def test_behind_one_proxy_the_client_is_the_address_the_proxy_saw(self):
        # nginx appends the address it received the request from, so with one
        # proxy the last entry is the real client and earlier ones are
        # whatever the client sent.
        rest_framework = {**settings.REST_FRAMEWORK, "NUM_PROXIES": 1}
        with override_settings(REST_FRAMEWORK=rest_framework):
            ident = self.ident(
                REMOTE_ADDR="127.0.0.1",
                HTTP_X_FORWARDED_FOR="6.6.6.6, 198.51.100.4",
            )

        self.assertEqual(ident, "198.51.100.4")

    def test_num_proxies_comes_from_the_environment(self):
        self.assertEqual(
            load_settings(**PRODUCTION_ENV).REST_FRAMEWORK["NUM_PROXIES"], 1
        )
        self.assertEqual(
            load_settings(DJANGO_DEBUG="True").REST_FRAMEWORK["NUM_PROXIES"], 0
        )


class ErrorLoggingTests(SimpleTestCase):
    def test_production_logs_unhandled_errors(self):
        # Django's default logging sends a 500's traceback to the console only
        # when DEBUG is on, and otherwise to mail_admins, with ADMINS empty:
        # in production a 500 left no trace anywhere.
        loaded = load_settings(**PRODUCTION_ENV)

        logger = loaded.LOGGING["loggers"]["django.request"]
        self.assertEqual(logger["level"], "ERROR")
        for name in logger["handlers"]:
            handler = loaded.LOGGING["handlers"][name]
            self.assertEqual(handler["class"], "logging.StreamHandler")
            # No require_debug_true filter, which is what silences Django's own.
            self.assertNotIn("filters", handler)
        self.assertTrue(logger["handlers"])
