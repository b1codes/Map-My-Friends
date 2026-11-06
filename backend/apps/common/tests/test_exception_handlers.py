from django.http import Http404
from django.test import SimpleTestCase
from google.api_core import exceptions as gcloud_exceptions
from rest_framework import exceptions as drf_exceptions
from rest_framework.permissions import AllowAny
from rest_framework.test import APIRequestFactory
from rest_framework.views import APIView

from apps.common.exception_handlers import firestore_exception_handler


class FirestoreExceptionHandlerTests(SimpleTestCase):
    """Calls the handler directly, the way DRF's APIView.handle_exception does."""

    def test_service_unavailable_maps_to_503(self):
        response = firestore_exception_handler(
            gcloud_exceptions.ServiceUnavailable("emulator down"), {}
        )
        self.assertEqual(response.status_code, 503)
        self.assertEqual(
            response.data,
            {"error": "Data store temporarily unavailable. Please retry."},
        )

    def test_deadline_exceeded_maps_to_503(self):
        response = firestore_exception_handler(
            gcloud_exceptions.DeadlineExceeded("rpc timed out"), {}
        )
        self.assertEqual(response.status_code, 503)

    def test_gcloud_not_found_maps_to_404(self):
        response = firestore_exception_handler(
            gcloud_exceptions.NotFound("No document to update"), {}
        )
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.data, {"error": "Not found."})

    def test_transport_detail_is_not_leaked(self):
        # The upstream message can carry project ids and document paths.
        response = firestore_exception_handler(
            gcloud_exceptions.ServiceUnavailable("projects/secret-project/..."), {}
        )
        self.assertNotIn("secret-project", str(response.data))

    def test_permission_denied_is_left_unhandled(self):
        # None tells DRF to re-raise, producing a logged 500 rather than a
        # user-facing response for what is really a credentials problem.
        self.assertIsNone(
            firestore_exception_handler(
                gcloud_exceptions.PermissionDenied("missing IAM role"), {}
            )
        )

    def test_unrelated_exceptions_are_left_unhandled(self):
        self.assertIsNone(firestore_exception_handler(ValueError("boom"), {}))
        self.assertIsNone(
            firestore_exception_handler(
                gcloud_exceptions.InternalServerError("backend error"), {}
            )
        )

    def test_drf_exceptions_still_use_the_default_handler(self):
        response = firestore_exception_handler(drf_exceptions.NotFound(), {})
        self.assertEqual(response.status_code, 404)
        # DRF's own shape ("detail"), not the Firestore one ("error").
        self.assertIn("detail", response.data)
        self.assertNotIn("error", response.data)

    def test_django_http404_still_uses_the_default_handler(self):
        response = firestore_exception_handler(Http404(), {})
        self.assertEqual(response.status_code, 404)
        self.assertIn("detail", response.data)


class _RaisingView(APIView):
    """Raises whatever exception the test hands it, as a Firestore call would."""

    permission_classes = [AllowAny]
    exc = None

    def get(self, request):
        raise self.exc


class ExceptionHandlerWiringTests(SimpleTestCase):
    """Proves settings.REST_FRAMEWORK actually routes views through the handler."""

    def _get(self, exc):
        view = _RaisingView.as_view(exc=exc)
        return view(APIRequestFactory().get("/boom/"))

    def test_view_raising_service_unavailable_returns_503(self):
        response = self._get(gcloud_exceptions.ServiceUnavailable("down"))
        self.assertEqual(response.status_code, 503)

    def test_view_raising_gcloud_not_found_returns_404(self):
        response = self._get(gcloud_exceptions.NotFound("gone"))
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.data, {"error": "Not found."})

    def test_view_raising_permission_denied_propagates(self):
        with self.assertRaises(gcloud_exceptions.PermissionDenied):
            self._get(gcloud_exceptions.PermissionDenied("bad credentials"))
