"""Settings for the DAST stack (docker-compose.dast.yml): production's
settings with the throttle rates raised and errors logged, and nothing else
changed.

The ZAP active scan sends a few thousand requests with one user's token. At
the real rates (2000/day per user, 10/minute for anonymous sign-ups) most of
them would get 429 Too Many Requests, and ZAP would be scanning the throttle
instead of the views behind it. The throttles themselves are tested in the
backend suite, so the scan doesn't need them.

Loaded with DJANGO_SETTINGS_MODULE=dast_settings and PYTHONPATH=/dast, so no
application code knows about it.
"""

from config.settings import *  # noqa: F403
from config.settings import REST_FRAMEWORK

REST_FRAMEWORK = {
    **REST_FRAMEWORK,
    "DEFAULT_THROTTLE_RATES": dict.fromkeys(
        REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"], "1000000/day"
    ),
}

# With DEBUG off, Django sends unhandled exceptions only to mail_admins, and
# ADMINS is empty, so a 500 leaves no trace in the logs. Print them, so a 500
# the scan provokes can be read in build/dast/stack.log. Responses are
# unchanged.
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "loggers": {"django.request": {"handlers": ["console"], "level": "ERROR"}},
}
