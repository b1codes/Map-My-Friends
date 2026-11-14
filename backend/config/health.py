"""/health: a liveness check for Cloud Run's startup and liveness probes.

It's middleware rather than a URL route so it can sit first in MIDDLEWARE and
answer before anything else runs. Probes call the container directly, over
plain HTTP, with a Host header that isn't the service's name, so a route
behind SecurityMiddleware (SECURE_SSL_REDIRECT) or CommonMiddleware
(ALLOWED_HOSTS) would be redirected or refused.

It says only that the process is up and serving. It deliberately doesn't check
Firestore: a slow second there shouldn't get a healthy instance restarted, and
a probe every few seconds shouldn't be a billed read. The post-deploy smoke
test (smoke/smoke.py) is what checks the API end to end.

The path doesn't end in "z" (as /healthz would): Cloud Run reserves those.
"""

from django.http import HttpResponseNotAllowed, JsonResponse

HEALTH_PATH = "/health"


class HealthCheckMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.path != HEALTH_PATH:
            return self.get_response(request)
        if request.method not in ("GET", "HEAD"):
            return HttpResponseNotAllowed(["GET", "HEAD"])
        response = JsonResponse({"status": "ok"})
        response["Cache-Control"] = "no-store"
        return response
