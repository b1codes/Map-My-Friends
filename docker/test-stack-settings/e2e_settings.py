"""Settings for the E2E stack only: the unthrottled test-stack settings, plus
the request log the request-budget journeys read (request_log.py).

The DAST and load-test stacks load unthrottled_settings.py instead, so the
scan never meets the log's route, and the load test doesn't pay for it.
"""

from unthrottled_settings import *  # noqa: F403
from unthrottled_settings import MIDDLEWARE

MIDDLEWARE = ["request_log.RequestLogMiddleware", *MIDDLEWARE]
ROOT_URLCONF = "e2e_urls"
