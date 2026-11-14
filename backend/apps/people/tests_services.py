import threading
from unittest.mock import MagicMock, patch

from django.core.exceptions import ValidationError
from django.test import SimpleTestCase, override_settings

from apps.people import services
from apps.people.services import GeocodingUnavailable, geocode_address


def forget_timezone_finders():
    """Each test patches TimezoneFinder, so none may reuse a cached one."""
    services._finders.__dict__.clear()


class GeocodeAddressTests(SimpleTestCase):
    def setUp(self):
        forget_timezone_finders()
        self.addCleanup(forget_timezone_finders)

    @patch("apps.people.services.TimezoneFinder")
    @patch("apps.people.services.Nominatim")
    def test_returns_coordinates_and_timezone(self, mock_nominatim, mock_tf):
        mock_nominatim.return_value.geocode.return_value = MagicMock(
            latitude=41.8781, longitude=-87.6298
        )
        mock_tf.return_value.timezone_at.return_value = "America/Chicago"

        lat, lng, tz = geocode_address("Chicago", "IL", "USA")

        self.assertAlmostEqual(lat, 41.8781)
        self.assertAlmostEqual(lng, -87.6298)
        self.assertEqual(tz, "America/Chicago")

    @patch("apps.people.services.TimezoneFinder")
    @patch("apps.people.services.Nominatim")
    def test_raises_validation_error_when_not_found(self, mock_nominatim, mock_tf):
        mock_nominatim.return_value.geocode.return_value = None

        with self.assertRaises(ValidationError):
            geocode_address("Nowhereville", "ZZ", "XX")

    @patch("apps.people.services.time.sleep")
    @patch("apps.people.services.TimezoneFinder")
    @patch("apps.people.services.Nominatim")
    def test_retries_on_timeout_then_succeeds(
        self, mock_nominatim, mock_tf, mock_sleep
    ):
        from geopy.exc import GeocoderTimedOut

        mock_nominatim.return_value.geocode.side_effect = [
            GeocoderTimedOut(),
            MagicMock(latitude=1.0, longitude=2.0),
        ]
        mock_tf.return_value.timezone_at.return_value = "UTC"

        lat, lng, tz = geocode_address("Somewhere", "ST", "CC")

        self.assertEqual((lat, lng, tz), (1.0, 2.0, "UTC"))
        self.assertEqual(mock_nominatim.return_value.geocode.call_count, 2)
        mock_sleep.assert_called_once_with(1)

    @patch("apps.people.services.time.sleep")
    @patch("apps.people.services.TimezoneFinder")
    @patch("apps.people.services.Nominatim")
    def test_raises_after_exhausting_retries(self, mock_nominatim, mock_tf, mock_sleep):
        from geopy.exc import GeocoderServiceError

        mock_nominatim.return_value.geocode.side_effect = GeocoderServiceError()

        with self.assertRaises(ValidationError):
            geocode_address("Somewhere", "ST", "CC")

        self.assertEqual(mock_nominatim.return_value.geocode.call_count, 3)

    @patch("apps.people.services.time.sleep")
    @patch("apps.people.services.TimezoneFinder")
    @patch("apps.people.services.Nominatim")
    def test_retries_three_times_when_not_found(
        self, mock_nominatim, mock_tf, mock_sleep
    ):
        mock_nominatim.return_value.geocode.return_value = None

        with self.assertRaises(ValidationError):
            geocode_address("Nowhereville", "ZZ", "XX")

        self.assertEqual(mock_nominatim.return_value.geocode.call_count, 3)

    @patch("apps.people.services.TimezoneFinder")
    @patch("apps.people.services.Nominatim")
    def test_street_included_in_query_when_provided(self, mock_nominatim, mock_tf):
        mock_nominatim.return_value.geocode.return_value = MagicMock(
            latitude=1.0, longitude=2.0
        )
        mock_tf.return_value.timezone_at.return_value = "UTC"

        geocode_address("Chicago", "IL", "USA", street="123 Main St")

        query = mock_nominatim.return_value.geocode.call_args[0][0]
        self.assertEqual(query["street"], "123 Main St")

    @patch("apps.people.services.time.sleep")
    @patch("apps.people.services.TimezoneFinder")
    @patch("apps.people.services.Nominatim")
    def test_outage_is_distinguishable_from_no_match(
        self, mock_nominatim, mock_tf, mock_sleep
    ):
        from geopy.exc import GeocoderServiceError

        mock_nominatim.return_value.geocode.side_effect = GeocoderServiceError()
        with self.assertRaises(GeocodingUnavailable):
            geocode_address("Somewhere", "ST", "CC")

        mock_nominatim.return_value.geocode.side_effect = None
        mock_nominatim.return_value.geocode.return_value = None
        with self.assertRaises(ValidationError) as caught:
            geocode_address("Nowhereville", "ZZ", "XX")
        self.assertNotIsInstance(caught.exception, GeocodingUnavailable)

    @override_settings(NOMINATIM_DOMAIN="stubs:8090", NOMINATIM_SCHEME="http")
    @patch("apps.people.services.TimezoneFinder")
    @patch("apps.people.services.Nominatim")
    def test_geocoder_host_comes_from_settings(self, mock_nominatim, mock_tf):
        mock_nominatim.return_value.geocode.return_value = MagicMock(
            latitude=41.8781, longitude=-87.6298
        )

        geocode_address("Chicago", "IL", "USA")

        mock_nominatim.assert_called_once_with(
            user_agent="map_my_friends_global_connect",
            domain="stubs:8090",
            scheme="http",
        )


@patch("apps.people.services.Nominatim")
class TimezoneFinderReuseTests(SimpleTestCase):
    """Building a TimezoneFinder costs about 300 ms of CPU, so a thread
    builds one once, not once per geocode."""

    def setUp(self):
        forget_timezone_finders()
        self.addCleanup(forget_timezone_finders)

    @patch("apps.people.services.TimezoneFinder")
    def test_one_thread_builds_one_finder(self, mock_tf, mock_nominatim):
        mock_nominatim.return_value.geocode.return_value = MagicMock(
            latitude=1.0, longitude=2.0
        )
        for city in ("London", "Paris", "Berlin"):
            geocode_address(city, "", "")
        self.assertEqual(mock_tf.call_count, 1)
        self.assertEqual(mock_tf.return_value.timezone_at.call_count, 3)

    @patch("apps.people.services.TimezoneFinder")
    def test_each_thread_builds_its_own(self, mock_tf, mock_nominatim):
        """The library's instances aren't safe to share between threads."""
        mock_nominatim.return_value.geocode.return_value = MagicMock(
            latitude=1.0, longitude=2.0
        )
        geocode_address("London", "", "")
        thread = threading.Thread(target=geocode_address, args=("Paris", "", ""))
        thread.start()
        thread.join()
        geocode_address("Berlin", "", "")
        self.assertEqual(mock_tf.call_count, 2)
