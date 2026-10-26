"""Address geocoding.

Lifted out of Person.save() when the model moved to Firestore. Behaviour
matches the original: same structured Nominatim query, same three attempts,
same ValidationError on failure. One deliberate improvement over the
original: a 1s delay is now inserted between attempts on the "not found"
path (not just the exception path), since Nominatim is rate-limited. It is
now an explicit call the repository makes, which also makes it testable
without touching the datastore.
"""

from __future__ import annotations

import time

from django.conf import settings
from django.core.exceptions import ValidationError
from django.utils.translation import gettext_lazy as _
from geopy.exc import GeocoderServiceError, GeocoderTimedOut
from geopy.geocoders import Nominatim
from timezonefinder import TimezoneFinder

USER_AGENT = "map_my_friends_global_connect"
MAX_ATTEMPTS = 3


class GeocodingUnavailable(ValidationError):
    """The geocoder could not be reached, as opposed to finding no match.

    A ValidationError subclass so existing callers that catch ValidationError
    keep working; callers that care can map an outage to a retryable error.
    """


def geocode_address(
    city: str,
    state: str,
    country: str,
    street: str | None = None,
) -> tuple[float, float, str | None]:
    """Resolve an address to (latitude, longitude, timezone).

    Raises ValidationError if the address cannot be resolved, or its subclass
    GeocodingUnavailable if the service is unavailable after MAX_ATTEMPTS.
    """
    geolocator = Nominatim(
        user_agent=USER_AGENT,
        domain=settings.NOMINATIM_DOMAIN,
        scheme=settings.NOMINATIM_SCHEME,
    )
    finder = TimezoneFinder()

    # Structured query gives better international accuracy than a free-text one.
    query = {"city": city, "state": state, "country": country}
    if street:
        query["street"] = street

    for attempt in range(MAX_ATTEMPTS):
        try:
            location = geolocator.geocode(query)
        except (GeocoderTimedOut, GeocoderServiceError):
            if attempt < MAX_ATTEMPTS - 1:
                time.sleep(1)
                continue
            raise GeocodingUnavailable(
                _("Geocoding service unavailable. Please try again later.")
            )

        if location:
            timezone = finder.timezone_at(lng=location.longitude, lat=location.latitude)
            return location.latitude, location.longitude, timezone

        if attempt < MAX_ATTEMPTS - 1:
            time.sleep(1)

    address = ", ".join(filter(None, [street or "", city, state, country])).strip(", ")
    raise ValidationError(
        _("Could not geocode address: %(address)s") % {"address": address}
    )
