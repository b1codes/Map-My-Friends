from django.contrib.auth.models import AnonymousUser, User
from django.test import RequestFactory, SimpleTestCase

from apps.common.ownership import owner_key_for


class OwnerKeyForTests(SimpleTestCase):
    def _request(self, user):
        request = RequestFactory().get("/")
        request.user = user
        return request

    def test_authenticated_user_maps_to_username(self):
        # An unsaved User is still authenticated; no database is needed.
        self.assertEqual(owner_key_for(self._request(User(username="ada"))), "ada")

    def test_anonymous_user_maps_to_public_dataset(self):
        self.assertIsNone(owner_key_for(self._request(AnonymousUser())))

    def test_missing_user_maps_to_public_dataset(self):
        self.assertIsNone(owner_key_for(self._request(None)))
