"""Rate limits on every throttled endpoint, tested at the exact limit.

Each test sends requests until the limit, checks the last allowed one still
gets through, and checks the next is a 429 with a Retry-After header. The
throttles are DRF's real classes with the real configured rates; only their
clock is replaced (SimpleRateThrottle.timer), so a day's budget can be spent
in a test without waiting a day, and windows can be shown to refill.

Most limits are cheap to reach with real requests: a throttle counts every
request it sees, including ones the view then rejects as invalid, so empty
bodies (400s) spend the budget without hashing passwords. The one exception
is the 2000/day user limit, where the history is pre-filled instead (see
UserThrottleTests.prime).
"""

from __future__ import annotations

import itertools
import unittest
from unittest.mock import patch

from django.contrib.auth.models import User
from django.core.cache import cache
from django.urls import reverse
from rest_framework.request import Request
from rest_framework.test import APIRequestFactory, APITestCase
from rest_framework.throttling import SimpleRateThrottle, UserRateThrottle
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from apps.common.testing import FirestoreTestMixin, ThrottleIsolationMixin

LONDON = (51.5074, -0.1278, "Europe/London")
PASSWORD = "Throttle!Pass123"
MINUTE = 60
DAY = 86400

_unique = itertools.count()


class FakeClock:
    """Stands in for SimpleRateThrottle.timer.

    An instance rather than a function: a plain function assigned to a class
    attribute becomes a method and would be called with the throttle as an
    argument. time.time doesn't have that problem because it's a builtin.
    """

    def __init__(self):
        self.now = 1_800_000_000.0

    def __call__(self):
        return self.now

    def advance(self, seconds):
        self.now += seconds


class ThrottleTestCase(ThrottleIsolationMixin, APITestCase):
    def setUp(self):
        super().setUp()
        self.clock = FakeClock()
        timer = patch.object(SimpleRateThrottle, "timer", self.clock)
        timer.start()
        self.addCleanup(timer.stop)

    def post(self, url, data=None, ip="10.0.0.1", **extra):
        return self.client.post(url, data or {}, format="json", REMOTE_ADDR=ip, **extra)

    def assert_not_throttled(self, response, label=""):
        self.assertNotEqual(response.status_code, 429, label)

    def assert_throttled(self, response, max_wait):
        self.assertEqual(response.status_code, 429)
        self.assertIn("Retry-After", response)
        wait = int(response["Retry-After"])
        self.assertGreater(wait, 0)
        self.assertLessEqual(wait, max_wait)
        return wait

    def spend(self, url, count, ip="10.0.0.1", **extra):
        """Send count requests that each pass the throttle."""
        for n in range(1, count + 1):
            self.assert_not_throttled(self.post(url, ip=ip, **extra), f"request {n}")


class ConfiguredRatesTests(ThrottleTestCase):
    def test_rates_match_the_documented_limits(self):
        """The behavior tests below assume these numbers; change both together."""
        self.assertEqual(
            SimpleRateThrottle.THROTTLE_RATES,
            {
                "anon": "100/day",
                "user": "2000/day",
                "anon_burst": "10/minute",
                "anon_sustained": "50/day",
            },
        )


class BurstLimitCases:
    """anon_burst: 10 requests a minute per IP. Mixed into a TestCase that
    sets url_name, success_status and valid_payload()."""

    url_name: str
    success_status: int

    def valid_payload(self) -> dict:
        raise NotImplementedError

    @property
    def url(self):
        return reverse(self.url_name)

    def test_burst_allows_ten_a_minute_then_429(self):
        self.spend(self.url, 9)
        tenth = self.post(self.url, self.valid_payload())
        self.assertEqual(tenth.status_code, self.success_status, tenth.data)

        eleventh = self.post(self.url, self.valid_payload())
        self.assert_throttled(eleventh, max_wait=MINUTE)

    def test_burst_window_refills_after_a_minute(self):
        self.spend(self.url, 10)
        self.clock.advance(59)
        self.assert_throttled(self.post(self.url), max_wait=MINUTE)
        self.clock.advance(2)
        self.assert_not_throttled(self.post(self.url))

    def test_burst_limit_is_per_client_ip(self):
        self.spend(self.url, 10, ip="10.0.0.1")
        self.assert_throttled(self.post(self.url, ip="10.0.0.1"), max_wait=MINUTE)
        self.assert_not_throttled(self.post(self.url, ip="10.0.0.2"))

    # Bug: the view's only throttles are AnonRateThrottle subclasses, and
    # AnonRateThrottle.get_cache_key returns None (never throttle) for any
    # authenticated request. The view is AllowAny, so sending any valid access
    # token, e.g. one for a throwaway account, turns the limit off entirely.
    @unittest.expectedFailure
    def test_signed_in_callers_are_limited_too(self):
        user = User.objects.create(username=f"token-holder-{next(_unique)}")
        auth = {"HTTP_AUTHORIZATION": f"Bearer {AccessToken.for_user(user)}"}
        self.spend(self.url, 10, **auth)
        self.assert_throttled(self.post(self.url, **auth), max_wait=MINUTE)


class SustainedLimitCases:
    """anon_sustained: 50 requests a day per IP, on top of the burst limit."""

    def test_sustained_allows_fifty_a_day_then_429(self):
        # Seven seconds apart keeps at most nine requests in any minute, so
        # the burst limit never trips and only the daily one is in play.
        for n in range(1, 51):
            self.assert_not_throttled(self.post(self.url), f"request {n}")
            self.clock.advance(7)

        wait = self.assert_throttled(self.post(self.url), max_wait=DAY)
        # A wait of hours, not seconds, shows it's the daily bucket that's full.
        self.assertGreater(wait, 3600)

    def test_sustained_limit_is_per_client_ip(self):
        for _ in range(50):
            self.post(self.url, ip="10.0.0.1")
            self.clock.advance(7)
        self.assert_throttled(self.post(self.url, ip="10.0.0.1"), max_wait=DAY)
        self.assert_not_throttled(self.post(self.url, ip="10.0.0.2"))


class RegisterThrottleTests(BurstLimitCases, SustainedLimitCases, ThrottleTestCase):
    url_name = "register"
    success_status = 201

    def valid_payload(self):
        n = next(_unique)
        return {
            "username": f"throttled-{n}",
            "email": f"throttled-{n}@example.com",
            "password": PASSWORD,
            "password_confirm": PASSWORD,
        }

    def test_throttled_registration_creates_no_account(self):
        self.spend(self.url, 10)
        payload = self.valid_payload()
        self.assert_throttled(self.post(self.url, payload), max_wait=MINUTE)
        self.assertFalse(User.objects.filter(username=payload["username"]).exists())


class PasswordResetThrottleTests(
    BurstLimitCases, SustainedLimitCases, ThrottleTestCase
):
    url_name = "password_reset"
    success_status = 200

    def valid_payload(self):
        return {"email": "someone@example.com"}


class PasswordResetConfirmThrottleTests(BurstLimitCases, ThrottleTestCase):
    """Confirm has the burst limit only. Its token is an HMAC, so a daily cap
    isn't what stops guessing; the burst limit just keeps the noise down."""

    url_name = "password_reset_confirm"
    # A well-formed request with a wrong token is refused, but it's a request
    # the throttle let through, which is what's being counted.
    success_status = 400

    def valid_payload(self):
        return {
            "user_id": 1,
            "token": "wrong-token",
            "password": PASSWORD,
            "password_confirm": PASSWORD,
        }


class SharedBurstBucketTests(ThrottleTestCase):
    def test_register_reset_and_confirm_share_one_burst_bucket(self):
        """All three throttle with scope anon_burst, and DRF keys the cache on
        scope plus IP, not on the view. So the budget is 10 a minute across
        the three, not 10 each: an attacker can't triple it by rotating
        endpoints. If they're ever split on purpose, change this test."""
        self.spend(reverse("register"), 4)
        self.spend(reverse("password_reset"), 3)
        self.spend(reverse("password_reset_confirm"), 3)
        for name in ("register", "password_reset", "password_reset_confirm"):
            with self.subTest(route=name):
                self.assert_throttled(self.post(reverse(name)), max_wait=MINUTE)


class LoginThrottleTests(ThrottleTestCase):
    """Token obtain has no throttle of its own, so it falls back to the
    default anon limit: 100 a day per IP."""

    def setUp(self):
        super().setUp()
        self.url = reverse("token_obtain_pair")
        self.user = User.objects.create_user(username="victim", password=PASSWORD)

    def test_login_allows_100_attempts_a_day_per_ip_then_429(self):
        self.spend(self.url, 99)
        hundredth = self.post(self.url, {"username": "victim", "password": "guess"})
        self.assertEqual(hundredth.status_code, 401)

        # Past the limit even the right password is refused, so a guesser
        # can't tell a hit from a miss.
        blocked = self.post(self.url, {"username": "victim", "password": PASSWORD})
        self.assert_throttled(blocked, max_wait=DAY)
        self.assertNotIn("access", blocked.data)

    def test_login_window_refills_after_a_day(self):
        self.spend(self.url, 100)
        self.clock.advance(DAY - 1)
        self.assert_throttled(self.post(self.url), max_wait=DAY)
        self.clock.advance(2)
        login = self.post(self.url, {"username": "victim", "password": PASSWORD})
        self.assertEqual(login.status_code, 200)

    def test_login_limit_is_per_client_ip(self):
        self.spend(self.url, 100, ip="10.0.0.1")
        self.assert_throttled(self.post(self.url, ip="10.0.0.1"), max_wait=DAY)
        login = self.post(
            self.url, {"username": "victim", "password": PASSWORD}, ip="10.0.0.2"
        )
        self.assertEqual(login.status_code, 200)

    def test_a_bearer_token_does_not_lift_the_login_limit(self):
        """Unlike register, token obtain ignores the Authorization header
        (authentication_classes is empty), so every caller is anonymous here
        and a token can't switch the anon throttle off."""
        auth = {"HTTP_AUTHORIZATION": f"Bearer {AccessToken.for_user(self.user)}"}
        self.spend(self.url, 100, **auth)
        self.assert_throttled(self.post(self.url, **auth), max_wait=DAY)

    # Gap: login has no burst limit, unlike register and password reset, so
    # one IP can make 100 password guesses back to back, and with N addresses
    # N * 100 a day against one account (nothing limits per username). 10 a
    # minute, the same anon_burst register uses, is the limit asserted here.
    @unittest.expectedFailure
    def test_login_has_a_burst_limit(self):
        self.spend(self.url, 10)
        guess = self.post(self.url, {"username": "victim", "password": "guess"})
        self.assert_throttled(guess, max_wait=MINUTE)


class TokenRefreshThrottleTests(ThrottleTestCase):
    """Token refresh, like login, falls back to the default anon limit."""

    def setUp(self):
        super().setUp()
        self.url = reverse("token_refresh")
        self.user = User.objects.create(username="refresher")

    def refresh_payload(self):
        return {"refresh": str(RefreshToken.for_user(self.user))}

    def test_refresh_allows_100_a_day_per_ip_then_429(self):
        self.spend(self.url, 99)
        hundredth = self.post(self.url, self.refresh_payload())
        self.assertEqual(hundredth.status_code, 200)

        blocked = self.post(self.url, self.refresh_payload())
        self.assert_throttled(blocked, max_wait=DAY)
        self.assertNotIn("access", blocked.data)

    def test_refresh_limit_is_per_client_ip(self):
        self.spend(self.url, 100, ip="10.0.0.1")
        self.assert_throttled(self.post(self.url, ip="10.0.0.1"), max_wait=DAY)
        other_ip = self.post(self.url, self.refresh_payload(), ip="10.0.0.2")
        self.assertEqual(other_ip.status_code, 200)


@patch("apps.people.views.geocode_address", return_value=LONDON)
class UserThrottleTests(FirestoreTestMixin, ThrottleTestCase):
    """Person create uses UserRateThrottle, 2000 a day per user."""

    collections_to_purge = ["people"]

    def setUp(self):
        super().setUp()
        self.url = reverse("person-list")
        self.alice = User.objects.create(username="alice")
        self.bob = User.objects.create(username="bob")
        self.client.force_authenticate(user=self.alice)

    def prime(self, user, count):
        """Record count requests for user, as if they had been made just now.

        2000 real requests would make this suite slow, so the history is
        written under the cache key the real UserRateThrottle computes, in
        the format it stores (a list of timestamps, newest first). If DRF
        changed either, the at-limit assertions below would fail rather than
        pass vacuously, and test_primed_and_real_requests_share_a_bucket shows
        primed entries and real requests count the same.
        """
        request = Request(APIRequestFactory().get("/"))
        request.user = user
        throttle = UserRateThrottle()
        key = throttle.get_cache_key(request, view=None)
        cache.set(key, [self.clock()] * count, throttle.duration)

    def create(self):
        return self.client.post(
            self.url, {"tag": "FRIEND", "first_name": "Ann"}, format="json"
        )

    def test_create_allows_2000_a_day_then_429(self, geocode):
        self.prime(self.alice, 1999)
        self.assertEqual(self.create().status_code, 201)

        geocode.reset_mock()
        self.assert_throttled(self.create(), max_wait=DAY)
        # The throttle runs before the view, so a throttled create never
        # reaches the geocoder, which is the cost it exists to protect.
        geocode.assert_not_called()

    def test_create_limit_is_per_user(self, geocode):
        self.prime(self.alice, 2000)
        self.assert_throttled(self.create(), max_wait=DAY)

        self.client.force_authenticate(user=self.bob)
        self.assertEqual(self.create().status_code, 201)

    def test_create_window_refills_after_a_day(self, geocode):
        self.prime(self.alice, 2000)
        self.clock.advance(DAY + 1)
        self.assertEqual(self.create().status_code, 201)

    def test_primed_and_real_requests_share_a_bucket(self, geocode):
        """One real request plus 1998 primed ones leaves room for exactly one
        create. That also shows the create bucket is the same "user" bucket
        every other signed-in request spends: a list counts against creates."""
        self.prime(self.alice, 1998)
        self.assertEqual(self.client.get(self.url).status_code, 200)
        self.assertEqual(self.create().status_code, 201)
        self.assert_throttled(self.create(), max_wait=DAY)
