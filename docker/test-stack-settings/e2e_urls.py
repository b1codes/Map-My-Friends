"""The app's URLs plus the E2E request log (request_log.py). Outside /api/,
so the log neither records itself nor counts as an API route."""

from django.urls import path
from request_log import requests_view

from config.urls import urlpatterns as app_urlpatterns

urlpatterns = [path("_e2e/requests/", requests_view), *app_urlpatterns]
