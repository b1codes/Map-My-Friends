from django.contrib.auth.models import User
from rest_framework.test import APITestCase

from apps.common import firestore as fs
from apps.common.testing import FirestoreTestMixin
from apps.users.repositories import UserProfileRepository


class UserProfileRepositoryTests(FirestoreTestMixin, APITestCase):
    collections_to_purge = ["user_profiles"]

    def test_get_or_create_is_idempotent(self):
        repo = UserProfileRepository()
        first = repo.get_or_create("owner-a")
        second = repo.get_or_create("owner-a")
        self.assertEqual(first.owner_key, second.owner_key)

    def test_defaults_applied(self):
        profile = UserProfileRepository().get_or_create("owner-a")
        self.assertEqual(profile.pin_color, "#2196F3")
        self.assertEqual(profile.distance_unit, "metric")

    def test_update_persists(self):
        repo = UserProfileRepository()
        repo.get_or_create("owner-a")
        updated = repo.update(
            "owner-a", {"city": "Chicago", "distance_unit": "imperial"}
        )
        self.assertEqual(updated.city, "Chicago")
        self.assertEqual(updated.distance_unit, "imperial")

    def test_profiles_are_isolated_by_key(self):
        repo = UserProfileRepository()
        repo.update("owner-a", {"city": "Chicago"})
        self.assertEqual(repo.get_or_create("owner-b").city, "")

    def test_update_creates_missing_profile_with_defaults(self):
        updated = UserProfileRepository().update("owner-a", {"city": "Chicago"})
        self.assertEqual(updated.city, "Chicago")
        self.assertEqual(updated.pin_color, "#2196F3")

    def test_update_ignores_non_profile_keys(self):
        repo = UserProfileRepository()
        updated = repo.update("owner-a", {"owner_key": "owner-b", "is_staff": True})
        self.assertEqual(updated.owner_key, "owner-a")
        self.assertNotIn(
            "is_staff",
            fs.collection("user_profiles").document("owner-a").get().to_dict(),
        )

    def test_unknown_stored_fields_are_ignored_on_read(self):
        # Documents written by older or newer code may carry extra fields;
        # hydration must not fail on them.
        fs.collection("user_profiles").document("owner-a").set(
            {"city": "Chicago", "legacy_field": "x"}
        )
        profile = UserProfileRepository().get_or_create("owner-a")
        self.assertEqual(profile.city, "Chicago")
        self.assertFalse(hasattr(profile, "legacy_field"))


class UserProfileEndpointTests(FirestoreTestMixin, APITestCase):
    collections_to_purge = ["user_profiles"]

    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(username="owner-a", password="pw12345!")

    def test_requires_authentication(self):
        self.assertEqual(self.client.get("/api/user/profile/").status_code, 401)

    def test_get_creates_profile_lazily(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.get("/api/user/profile/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["pin_color"], "#2196F3")

    def test_patch_updates_profile(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.patch(
            "/api/user/profile/", {"city": "Chicago"}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["city"], "Chicago")


class ProfileNameWriteTests(FirestoreTestMixin, APITestCase):
    """first_name/last_name live on the Django User, not the Firestore doc.

    The Flutter client sends a name-only PATCH body when only the name is
    edited, which previously filtered to an empty Firestore update and 500'd.
    """

    collections_to_purge = ["user_profiles"]

    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(
            username="owner-a", password="pw12345!", first_name="Old", last_name="Name"
        )
        self.client.force_authenticate(user=self.user)

    def test_name_only_patch_succeeds_and_persists(self):
        response = self.client.patch(
            "/api/user/profile/",
            {"first_name": "New", "last_name": "Person"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["first_name"], "New")

        self.user.refresh_from_db()
        self.assertEqual(self.user.first_name, "New")
        self.assertEqual(self.user.last_name, "Person")

    def test_name_and_profile_field_together(self):
        response = self.client.patch(
            "/api/user/profile/",
            {"first_name": "Both", "city": "Chicago"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["first_name"], "Both")
        self.assertEqual(response.data["city"], "Chicago")
