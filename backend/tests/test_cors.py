"""The web app calls the API cross-origin (Firebase Hosting to Cloud Run), so
every request header it sends must pass the browser's CORS preflight."""

from django.test import SimpleTestCase, override_settings

ORIGIN = "https://app.example.com"


@override_settings(CORS_ALLOW_ALL_ORIGINS=False, CORS_ALLOWED_ORIGINS=[ORIGIN])
class PreflightTests(SimpleTestCase):
    def preflight(self, path, method, headers):
        return self.client.options(
            path,
            HTTP_ORIGIN=ORIGIN,
            HTTP_ACCESS_CONTROL_REQUEST_METHOD=method,
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS=headers,
        )

    def allowed_headers(self, response):
        return {
            h.strip().lower()
            for h in response.headers.get("Access-Control-Allow-Headers", "").split(",")
        }

    def test_a_person_create_may_carry_an_idempotency_key(self):
        response = self.preflight(
            "/api/people/", "POST", "authorization,content-type,idempotency-key"
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers.get("Access-Control-Allow-Origin"), ORIGIN)
        self.assertLessEqual(
            {"authorization", "content-type", "idempotency-key"},
            self.allowed_headers(response),
        )
