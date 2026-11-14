"""Settings for the throwaway test stacks: the app's settings with the throttle
rates raised, and nothing else changed.

Used by the E2E stack (docker-compose.e2e.yml) and the DAST stack on top of it
(docker-compose.dast.yml). Both send far more requests from one address, and
as one user, than a person would: the E2E journeys sign up and sign in dozens
of times a minute, and the ZAP active scan sends thousands of requests with
one user's token. At the real rates (10 sign-ins a minute per IP, 2000
requests a day per user) they'd get 429 Too Many Requests and test the
throttle instead of the views behind it. The throttles themselves are tested
exactly in backend/tests/test_throttling.py.

Loaded with DJANGO_SETTINGS_MODULE=unthrottled_settings and
PYTHONPATH=/test-stack-settings, so no application code knows about it and
production can't pick it up.
"""

from config.settings import *  # noqa: F403
from config.settings import REST_FRAMEWORK

# Every scope settings defines, so a new one is raised too.
REST_FRAMEWORK = {
    **REST_FRAMEWORK,
    "DEFAULT_THROTTLE_RATES": dict.fromkeys(
        REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"], "1000000/day"
    ),
}
