"""Stand-ins for the public services the app calls, for the E2E stack.

The E2E journeys run the real app against the real API, but they must not
depend on volunteer-run servers that rate-limit, change their data, or go
down: Nominatim (the API geocodes addresses), OSRM (both the API and the app
route between stops) and OpenStreetMap tiles (the map). The shapes these
services return are pinned by the contract tests in contracts/, and checked
against the real servers nightly, so a stub only has to answer in that shape.

Answers are deterministic:
- /search geocodes the cities in CITIES and finds nothing for any other city,
  so a journey can exercise the "address not found" path on purpose.
- /route/v1/driving/... returns a three-point route through a midpoint nudged
  off the straight line, so a drawn route is distinguishable from the app's
  straight-line fallback.
- /tiles/{z}/{x}/{y}.png returns one plain tile.

Every request is recorded; GET /_stub/requests lists them and DELETE clears
them, so a journey can assert what the app actually called.

Standard library only, so it runs on a stock python image.
"""

from __future__ import annotations

import json
import re
import struct
import threading
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

PORT = 8090

# city (lower case) -> (lat, lon). Real coordinates, so timezone lookup and
# nearest-airport/station queries return realistic results.
CITIES = {
    "berlin": (52.5200, 13.4050),
    "boston": (42.3601, -71.0589),
    "chicago": (41.8781, -87.6298),
    "london": (51.5074, -0.1278),
    "new york": (40.7128, -74.0060),
    "paris": (48.8566, 2.3522),
    "san francisco": (37.7749, -122.4194),
    "seattle": (47.6062, -122.3321),
    "tokyo": (35.6762, 139.6503),
    "toronto": (43.6532, -79.3832),
}

ROUTE_PATH = re.compile(r"^/route/v1/driving/([^/?]+)$")
TILE_PATH = re.compile(r"^/tiles/\d+/\d+/\d+\.png$")


def _png(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    row = b"\x00" + bytes(rgb) * width
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(row * height))
        + chunk(b"IEND", b"")
    )


TILE = _png(256, 256, (232, 236, 239))

_requests: list[dict] = []
_requests_lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    server_version = "e2e-stubs"

    def log_message(self, format, *args):  # noqa: A002 - BaseHTTPRequestHandler API
        pass  # The request log below is the useful record; stderr is noise.

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        # The app calls OSRM and loads tiles straight from the browser.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        # DELETE (clearing the log from a journey) isn't CORS-safelisted.
        self.send_header("Access-Control-Allow-Methods", "GET, DELETE, OPTIONS")
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status: int, payload) -> None:
        self._send(status, json.dumps(payload).encode(), "application/json")

    def do_OPTIONS(self):  # noqa: N802
        self._send(204, b"", "text/plain")

    def do_DELETE(self):  # noqa: N802
        if urlsplit(self.path).path == "/_stub/requests":
            with _requests_lock:
                _requests.clear()
            self._json(200, {"cleared": True})
            return
        self._json(404, {"error": "not found"})

    def do_GET(self):  # noqa: N802
        url = urlsplit(self.path)
        query = {k: v[0] for k, v in parse_qs(url.query).items()}

        if url.path == "/_stub/health":
            self._json(200, {"ok": True})
            return
        if url.path == "/_stub/requests":
            with _requests_lock:
                self._json(200, list(_requests))
            return

        with _requests_lock:
            _requests.append({"path": url.path, "query": query})

        if url.path == "/search":
            self._json(200, self._geocode(query))
        elif match := ROUTE_PATH.match(url.path):
            self._json(200, self._route(match.group(1)))
        elif TILE_PATH.match(url.path):
            self._send(200, TILE, "image/png")
        else:
            self._json(404, {"error": f"no stub for {url.path}"})

    @staticmethod
    def _geocode(query: dict) -> list[dict]:
        """Nominatim /search, as geopy's structured query calls it."""
        city = (query.get("city") or "").strip().lower()
        if city not in CITIES:
            return []
        lat, lon = CITIES[city]
        name = ", ".join(
            filter(None, [query.get("city"), query.get("state"), query.get("country")])
        )
        return [
            {
                "place_id": abs(hash(city)) % 10**8,
                "lat": f"{lat}",
                "lon": f"{lon}",
                "display_name": name,
                "class": "place",
                "type": "city",
                "importance": 0.8,
            }
        ]

    @staticmethod
    def _route(coords: str) -> dict:
        """OSRM /route/v1/driving/{lon,lat;lon,lat...}."""
        try:
            points = [[float(n) for n in pair.split(",")] for pair in coords.split(";")]
        except ValueError:
            return {"code": "InvalidUrl", "message": "Bad coordinates"}
        if len(points) < 2:
            return {"code": "InvalidQuery", "message": "Need two coordinates"}

        line = [points[0]]
        for start, end in zip(points, points[1:], strict=False):
            mid = [(start[0] + end[0]) / 2 + 0.05, (start[1] + end[1]) / 2 + 0.05]
            line += [mid, end]
        return {
            "code": "Ok",
            "routes": [
                {
                    "geometry": {"type": "LineString", "coordinates": line},
                    "distance": 1000.0 * (len(points) - 1),
                    "duration": 600.0 * (len(points) - 1),
                    "weight": 600.0 * (len(points) - 1),
                    "weight_name": "routability",
                    "legs": [],
                }
            ],
            "waypoints": [{"location": p, "name": ""} for p in points],
        }


if __name__ == "__main__":
    print(f"e2e stubs listening on :{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
