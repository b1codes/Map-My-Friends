"""Pure geodesic helpers. Deliberately free of Django imports so the
reference indexes can be unit-tested without database or settings setup."""

from __future__ import annotations

import math

# Mean Earth radius (WGS-84 authalic), kilometres.
EARTH_RADIUS_KM = 6371.0088


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance between two WGS-84 points, in kilometres."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lng2 - lng1)

    a = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    )
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


def parse_lat_lon(lat, lon) -> tuple[float, float]:
    """Parse raw lat/lon query values into a valid WGS-84 coordinate pair.

    Raises ValueError carrying a client-facing message. float() alone is not
    enough: it accepts "inf", "nan" and overflowing literals such as "1e309",
    which make haversine_km raise, and it accepts out-of-range values that
    would silently produce meaningless "nearest" results.
    """
    try:
        lat, lon = float(lat), float(lon)
    except (TypeError, ValueError):
        raise ValueError(
            "lat and lon query parameters are required and must be numbers."
        ) from None
    # NaN fails every comparison and ±inf falls outside the bounds, so the
    # range check rejects non-finite values too.
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError("lat must be between -90 and 90 and lon between -180 and 180.")
    return lat, lon
