from unittest.mock import MagicMock, patch

import requests
from django.test import SimpleTestCase

from apps.trips.services import OSRMService, RoutingError, TransportLookupService

CHICAGO = [-87.6298, 41.8781]
LONDON = [-0.1278, 51.5074]
GEOMETRY = {"type": "LineString", "coordinates": [CHICAGO, LONDON]}


def osrm_response(body):
    response = MagicMock()
    response.json.return_value = body
    return response


@patch("apps.trips.services.requests.get")
class OSRMServiceTests(SimpleTestCase):
    def test_returns_first_route_geometry(self, mock_get):
        mock_get.return_value = osrm_response(
            {
                "code": "Ok",
                "routes": [{"geometry": GEOMETRY}, {"geometry": {"other": True}}],
            }
        )

        self.assertEqual(OSRMService.get_route([CHICAGO, LONDON]), GEOMETRY)

    def test_builds_lon_lat_url_with_timeout(self, mock_get):
        mock_get.return_value = osrm_response(
            {"code": "Ok", "routes": [{"geometry": GEOMETRY}]}
        )

        OSRMService.get_route([CHICAGO, LONDON])

        mock_get.assert_called_once_with(
            "https://router.project-osrm.org/route/v1/driving/"
            "-87.6298,41.8781;-0.1278,51.5074?overview=full&geometries=geojson",
            timeout=10,
        )

    def test_rejects_fewer_than_two_coordinates(self, mock_get):
        for coordinates in ([], [CHICAGO]):
            with (
                self.subTest(count=len(coordinates)),
                self.assertRaisesMessage(
                    RoutingError, "At least two coordinates are required."
                ),
            ):
                OSRMService.get_route(coordinates)
        mock_get.assert_not_called()

    def test_accepts_exactly_twenty_five_coordinates(self, mock_get):
        mock_get.return_value = osrm_response(
            {"code": "Ok", "routes": [{"geometry": GEOMETRY}]}
        )
        OSRMService.get_route([CHICAGO] * 25)
        mock_get.assert_called_once()

    def test_rejects_more_than_twenty_five_coordinates(self, mock_get):
        with self.assertRaisesMessage(RoutingError, "Maximum of 25 coordinates"):
            OSRMService.get_route([CHICAGO] * 26)
        mock_get.assert_not_called()

    def test_non_ok_code_raises_with_upstream_message(self, mock_get):
        mock_get.return_value = osrm_response(
            {"code": "InvalidQuery", "message": "Query string malformed"}
        )
        with self.assertRaisesMessage(
            RoutingError, "OSRM returned error: Query string malformed"
        ):
            OSRMService.get_route([CHICAGO, LONDON])

    def test_ok_without_routes_raises_no_route_found(self, mock_get):
        mock_get.return_value = osrm_response({"code": "Ok", "routes": []})
        with self.assertRaisesMessage(
            RoutingError, "OSRM returned error: No route found"
        ):
            OSRMService.get_route([CHICAGO, LONDON])

    def test_http_error_is_wrapped(self, mock_get):
        response = osrm_response({})
        response.raise_for_status.side_effect = requests.HTTPError("502 Bad Gateway")
        mock_get.return_value = response

        with self.assertRaisesMessage(
            RoutingError, "External routing service error: 502 Bad Gateway"
        ):
            OSRMService.get_route([CHICAGO, LONDON])

    def test_network_errors_are_wrapped(self, mock_get):
        for exc in (requests.Timeout("timed out"), requests.ConnectionError("down")):
            with self.subTest(type(exc).__name__):
                mock_get.side_effect = exc
                with self.assertRaises(RoutingError) as ctx:
                    OSRMService.get_route([CHICAGO, LONDON])
                self.assertEqual(ctx.exception.status_code, 400)
                self.assertIn("External routing service error", str(ctx.exception))

    def test_non_json_body_is_wrapped(self, mock_get):
        response = osrm_response(None)
        response.json.side_effect = requests.JSONDecodeError("Expecting value", "", 0)
        mock_get.return_value = response

        with self.assertRaisesMessage(RoutingError, "External routing service error"):
            OSRMService.get_route([CHICAGO, LONDON])


class TransportLookupServiceTests(SimpleTestCase):
    def test_known_flight_is_case_insensitive(self):
        for number in ("BA123", "ba123"):
            with self.subTest(number):
                result = TransportLookupService.lookup_flight(number)
                self.assertEqual(result["airline"], "British Airways")
                self.assertEqual(result["departure"]["iata"], "LHR")
                self.assertEqual(result["arrival"]["time"], "2026-07-04T13:00:00Z")

    def test_unknown_flight_returns_empty(self):
        self.assertEqual(TransportLookupService.lookup_flight("UA1"), {})

    def test_amtrak_train_matches_anywhere_in_identifier(self):
        for number in ("AMT171", "amtrak-171", "NE-amt"):
            with self.subTest(number):
                result = TransportLookupService.lookup_train(number)
                self.assertEqual(result["departure"]["station"], "PHL")
                self.assertEqual(result["arrival"]["station"], "WAS")

    def test_unknown_train_returns_empty(self):
        self.assertEqual(TransportLookupService.lookup_train("ICE 123"), {})
