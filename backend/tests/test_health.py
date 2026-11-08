"""/health: the liveness check Cloud Run's startup and liveness probes call.

The probes reach the container directly, over plain HTTP, with whatever Host
header the platform sends. So the route must answer before anything that would
refuse or redirect such a request (ALLOWED_HOSTS, SECURE_SSL_REDIRECT), and
without touching Firestore: an instance shouldn't be restarted because
Firestore had a slow second, and a probe shouldn't cost a billed read.
"""

from unittest import mock

from django.test import SimpleTestCase, override_settings


class HealthTests(SimpleTestCase):
    def test_answers_ok(self):
        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_answers_a_head_request(self):
        self.assertEqual(self.client.head("/health").status_code, 200)

    def test_refuses_other_methods(self):
        response = self.client.post("/health")

        self.assertEqual(response.status_code, 405)
        self.assertEqual(response["Allow"], "GET, HEAD")

    @override_settings(ALLOWED_HOSTS=["api.example.com"])
    def test_answers_whatever_host_the_probe_sends(self):
        # A probe's Host is the instance's own address, never the service's
        # public name, which is all ALLOWED_HOSTS lists in production.
        response = self.client.get("/health", HTTP_HOST="169.254.8.1:8080")

        self.assertEqual(response.status_code, 200)

    @override_settings(SECURE_SSL_REDIRECT=True)
    def test_answers_over_plain_http(self):
        # Probes don't go through Google's front end, so there's no TLS and no
        # X-Forwarded-Proto. A redirect to https would fail every probe.
        self.assertEqual(self.client.get("/health").status_code, 200)

    def test_does_not_touch_firestore(self):
        with mock.patch(
            "apps.common.firestore.get_client",
            side_effect=AssertionError("/health read Firestore"),
        ):
            self.assertEqual(self.client.get("/health").status_code, 200)

    def test_is_not_cached(self):
        self.assertIn("no-store", self.client.get("/health")["Cache-Control"])

    def test_only_the_exact_path(self):
        # Anything else goes through the normal stack; with DEBUG off the test
        # client's host is refused before routing, so 400 rather than 404.
        with override_settings(ALLOWED_HOSTS=["api.example.com"]):
            response = self.client.get("/health/extra", HTTP_HOST="169.254.8.1")

        self.assertEqual(response.status_code, 400)
