"""A log of the API requests the E2E stack answers, for the journeys to read.

The request-budget journeys (frontend/integration_test/journeys/
requests_test.dart) open the real app and check how many requests it sent,
by route. The app has five HTTP clients, one of them made per call, so
counting in the app would miss some; the API sees all of them.

RequestLogMiddleware records every /api/ request as method, path, status and
the signed-in username (blank for anonymous ones). GET /_e2e/requests/?user=
<username> lists that user's, oldest first, and DELETE clears the log.

Loaded only by e2e_settings.py, which only docker-compose.e2e.yml uses, so no
other stack serves it.
"""

from __future__ import annotations

import threading

from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt

_lock = threading.Lock()
_log: list[dict] = []


class RequestLogMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        if request.path.startswith("/api/"):
            # DRF authenticates in the view and sets the user on the Django
            # request then, so it's known by the time the response is.
            user = getattr(request, "user", None)
            entry = {
                "method": request.method,
                "path": request.path,
                "status": response.status_code,
                "user": user.get_username() if user and user.is_authenticated else "",
            }
            with _lock:
                _log.append(entry)
        return response


@csrf_exempt
def requests_view(request):
    if request.method == "DELETE":
        with _lock:
            _log.clear()
        return JsonResponse({"cleared": True})
    username = request.GET.get("user")
    with _lock:
        entries = [e for e in _log if username is None or e["user"] == username]
    return JsonResponse(entries, safe=False)
