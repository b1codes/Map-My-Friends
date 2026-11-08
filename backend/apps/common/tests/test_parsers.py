"""JSON that is well formed but not valid Unicode.

JSON may spell a UTF-16 surrogate on its own ("\\ud800"), and Python decodes
it into a str that can't be encoded as UTF-8. DRF accepted it, and a
response that echoed it back (a validation message, the saved record)
failed to render: a 500 on every route that takes a body. Firestore stores
UTF-8 too. Found by the API fuzz test (tests/test_fuzz_api.py), so the API
now refuses such a body with a 400 before any view sees it.
"""

import io

from django.contrib.auth.models import User
from django.urls import URLPattern, URLResolver, get_resolver
from rest_framework.exceptions import ParseError
from rest_framework.parsers import JSONParser
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken

from apps.common.parsers import StrictJSONParser
from apps.common.testing import FirestoreTestMixin, ThrottleIsolationMixin


def parse(text: str):
    return StrictJSONParser().parse(io.BytesIO(text.encode()))


class StrictJSONParserTests(APITestCase):
    def test_lone_surrogates_are_refused_wherever_they_are(self):
        for text in (
            r'"\ud800"',
            r'{"first_name": "a\udfffb"}',
            r'{"\ud83e": 1}',
            r'{"stops": [{"people": ["\udc00"]}]}',
            r'[[["\ud800"]]]',
        ):
            with (
                self.subTest(text=text),
                self.assertRaisesMessage(ParseError, "valid Unicode"),
            ):
                parse(text)

    def test_a_surrogate_pair_is_one_character_and_fine(self):
        self.assertEqual(parse(r'{"pin_emoji": "🦄"}'), {"pin_emoji": "🦄"})

    def test_ordinary_json_is_unchanged(self):
        body = {"name": "Zoë", "n": 1, "x": [None, True, 2.5], "nested": {"a": "b"}}
        self.assertEqual(
            parse(
                '{"name": "Zoë", "n": 1, "x": [null, true, 2.5], "nested": {"a": "b"}}'
            ),
            body,
        )

    def test_every_api_view_uses_it(self):
        """A view that lists its own parsers must list the strict one, or it
        brings the 500 back."""
        for view in _api_views():
            for parser in view.parser_classes:
                with self.subTest(view=view.__name__, parser=parser.__name__):
                    self.assertFalse(
                        issubclass(parser, JSONParser)
                        and not issubclass(parser, StrictJSONParser),
                    )


def _api_views():
    def walk(patterns):
        for pattern in patterns:
            if isinstance(pattern, URLResolver):
                yield from walk(pattern.url_patterns)
            elif isinstance(pattern, URLPattern):
                cls = getattr(pattern.callback, "cls", None)
                if cls is not None and hasattr(cls, "parser_classes"):
                    yield cls

    return set(walk(get_resolver().url_patterns))


class LoneSurrogateRequestTests(
    ThrottleIsolationMixin, FirestoreTestMixin, APITestCase
):
    collections_to_purge = ["people", "user_profiles"]

    def setUp(self):
        super().setUp()
        user = User.objects.create_user(username="ada", password="x")
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {AccessToken.for_user(user)}"
        )

    def send(self, method, url, raw):
        return self.client.generic(method, url, raw, content_type="application/json")

    def test_routes_that_take_a_body_answer_400(self):
        # Each value lands in a field whose error message quotes it back:
        # '"\ud800" is not a valid choice.' That echo is what failed to render.
        for method, url, raw in (
            ("POST", "/api/people/", r'{"first_name": "A", "pin_style": "\ud800"}'),
            ("PATCH", "/api/user/profile/", r'{"pin_icon_type": "\ud800"}'),
            ("POST", "/api/trips/", r'{"name": "T", "status": "\ud800"}'),
            (
                "POST",
                "/api/contact-logs/",
                r'{"person": "p", "channel": "\ud800"}',
            ),
        ):
            with self.subTest(method=method, url=url):
                response = self.send(method, url, raw)
                self.assertEqual(response.status_code, 400)
                self.assertIn("valid Unicode", response.json()["detail"])
