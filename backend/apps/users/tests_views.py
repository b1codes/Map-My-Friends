"""Endpoint tests for profile, registration, password reset and token views."""

import io
import shutil
import tempfile

from django.contrib.auth.models import User
from django.contrib.auth.tokens import default_token_generator
from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from PIL import Image
from rest_framework.test import APITestCase

from apps.common.testing import FirestoreTestMixin, ThrottleIsolationMixin
from apps.users.repositories import UserProfileRepository

PROFILE_URL = "/api/user/profile/"
REGISTER_URL = "/api/user/auth/register/"
TOKEN_URL = "/api/user/auth/token/"
REFRESH_URL = "/api/user/auth/token/refresh/"
RESET_URL = "/api/user/auth/password-reset/"
RESET_CONFIRM_URL = "/api/user/auth/password-reset/confirm/"

STRONG_PASSWORD = "Tr1cky-Horse-Battery"
NEW_PASSWORD = "Another-Str0ng-Secret"


def png_upload(name="avatar.png"):
    buffer = io.BytesIO()
    Image.new("RGB", (2, 2), color="red").save(buffer, format="PNG")
    return SimpleUploadedFile(name, buffer.getvalue(), content_type="image/png")


class ProfileUpdateTests(FirestoreTestMixin, APITestCase):
    collections_to_purge = ["user_profiles"]

    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(
            username="owner-a", email="a@example.com", password="pw12345!"
        )
        self.client.force_authenticate(user=self.user)
        self.profiles = UserProfileRepository()

    def test_get_includes_account_fields_from_django_user(self):
        self.user.first_name = "Ada"
        self.user.last_name = "Lovelace"
        self.user.save()

        response = self.client.get(PROFILE_URL)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["username"], "owner-a")
        self.assertEqual(response.data["email"], "a@example.com")
        self.assertEqual(response.data["first_name"], "Ada")
        self.assertEqual(response.data["last_name"], "Lovelace")
        self.assertIsNone(response.data["profile_image"])

    def test_invalid_choice_is_rejected_without_writing(self):
        response = self.client.patch(
            PROFILE_URL, {"pin_style": "hexagon", "city": "Chicago"}, format="json"
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("pin_style", response.data)
        # Validation is all-or-nothing: the valid field must not sneak through.
        self.assertEqual(self.profiles.get_or_create("owner-a").city, "")

    def test_overlong_pin_color_is_rejected(self):
        response = self.client.patch(
            PROFILE_URL, {"pin_color": "#12345678"}, format="json"
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("pin_color", response.data)

    def test_invalid_birth_date_is_rejected(self):
        response = self.client.patch(
            PROFILE_URL, {"birth_date": "17/05/1990"}, format="json"
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("birth_date", response.data)

    def test_birth_date_is_stored_as_iso_string(self):
        response = self.client.patch(
            PROFILE_URL, {"birth_date": "1990-05-17"}, format="json"
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["birth_date"], "1990-05-17")
        # Firestore cannot encode datetime.date; the view must write a string.
        self.assertEqual(
            self.profiles.get_or_create("owner-a").birth_date, "1990-05-17"
        )

    def test_birth_date_can_be_cleared(self):
        self.profiles.update("owner-a", {"birth_date": "1990-05-17"})

        response = self.client.patch(PROFILE_URL, {"birth_date": None}, format="json")

        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.data["birth_date"])
        self.assertIsNone(self.profiles.get_or_create("owner-a").birth_date)

    def test_pin_preferences_round_trip(self):
        payload = {
            "pin_color": "#FF0000",
            "pin_style": "diamond",
            "pin_icon_type": "emoji",
            "pin_emoji": "🦊",
            "distance_unit": "imperial",
        }

        self.client.patch(PROFILE_URL, payload, format="json")
        response = self.client.get(PROFILE_URL)

        for field, value in payload.items():
            self.assertEqual(response.data[field], value, field)

    def test_profiles_are_scoped_to_the_requesting_user(self):
        other = User.objects.create_user(username="owner-b", password="pw12345!")
        self.client.patch(PROFILE_URL, {"city": "Chicago"}, format="json")

        self.client.force_authenticate(user=other)
        response = self.client.get(PROFILE_URL)

        self.assertEqual(response.data["city"], "")
        self.assertEqual(response.data["username"], "owner-b")


class ProfileImageUploadTests(FirestoreTestMixin, APITestCase):
    collections_to_purge = ["user_profiles"]

    def setUp(self):
        super().setUp()
        media_root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, media_root, ignore_errors=True)
        media = override_settings(MEDIA_ROOT=media_root)
        media.enable()
        self.addCleanup(media.disable)

        self.user = User.objects.create_user(username="owner-a", password="pw12345!")
        self.client.force_authenticate(user=self.user)

    def test_upload_is_saved_and_exposed_as_absolute_url(self):
        response = self.client.patch(
            PROFILE_URL,
            {"profile_image": png_upload("Avatar.PNG"), "city": "Chicago"},
            format="multipart",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["city"], "Chicago")

        stored = UserProfileRepository().get_or_create("owner-a").profile_image
        # A random stem avoids collisions; the extension is normalised.
        self.assertRegex(stored, r"^user_profiles/[0-9a-f]{32}\.png$")
        self.assertTrue(default_storage.exists(stored))
        self.assertEqual(
            response.data["profile_image"], f"http://testserver/media/{stored}"
        )

    def test_uploaded_image_persists_across_requests(self):
        uploaded = self.client.patch(
            PROFILE_URL, {"profile_image": png_upload()}, format="multipart"
        )

        response = self.client.get(PROFILE_URL)

        self.assertEqual(response.data["profile_image"], uploaded.data["profile_image"])

    def test_patch_without_file_keeps_existing_image(self):
        uploaded = self.client.patch(
            PROFILE_URL, {"profile_image": png_upload()}, format="multipart"
        )

        response = self.client.patch(PROFILE_URL, {"city": "Chicago"}, format="json")

        self.assertEqual(response.data["profile_image"], uploaded.data["profile_image"])


class RegisterTests(ThrottleIsolationMixin, APITestCase):
    def payload(self, **overrides):
        data = {
            "username": "newuser",
            "email": "new@example.com",
            "password": STRONG_PASSWORD,
            "password_confirm": STRONG_PASSWORD,
            "first_name": "New",
            "last_name": "User",
        }
        data.update(overrides)
        return data

    def test_register_creates_user_with_hashed_password(self):
        response = self.client.post(REGISTER_URL, self.payload(), format="json")

        self.assertEqual(response.status_code, 201)
        user = User.objects.get(username="newuser")
        self.assertEqual(user.email, "new@example.com")
        self.assertEqual(user.first_name, "New")
        self.assertEqual(user.last_name, "User")
        self.assertNotEqual(user.password, STRONG_PASSWORD)
        self.assertTrue(user.check_password(STRONG_PASSWORD))

    def test_response_never_echoes_secrets(self):
        response = self.client.post(REGISTER_URL, self.payload(), format="json")

        self.assertEqual(
            set(response.data), {"username", "email", "first_name", "last_name"}
        )

    def test_registered_user_can_obtain_tokens(self):
        self.client.post(REGISTER_URL, self.payload(), format="json")

        response = self.client.post(
            TOKEN_URL, {"username": "newuser", "password": STRONG_PASSWORD}
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn("access", response.data)

    def test_names_are_optional(self):
        payload = self.payload()
        del payload["first_name"], payload["last_name"]

        response = self.client.post(REGISTER_URL, payload, format="json")

        self.assertEqual(response.status_code, 201)
        self.assertEqual(User.objects.get(username="newuser").first_name, "")

    def test_mismatched_passwords_are_rejected(self):
        response = self.client.post(
            REGISTER_URL,
            self.payload(password_confirm="Different-Pass-99"),
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("password", response.data)
        self.assertFalse(User.objects.filter(username="newuser").exists())

    def test_weak_password_is_rejected(self):
        response = self.client.post(
            REGISTER_URL,
            self.payload(password="12345678", password_confirm="12345678"),
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("password", response.data)
        self.assertFalse(User.objects.filter(username="newuser").exists())

    def test_duplicate_email_is_rejected(self):
        User.objects.create_user(username="existing", email="new@example.com")

        response = self.client.post(REGISTER_URL, self.payload(), format="json")

        self.assertEqual(response.status_code, 400)
        self.assertIn("email", response.data)
        self.assertFalse(User.objects.filter(username="newuser").exists())

    def test_duplicate_username_is_rejected(self):
        User.objects.create_user(username="newuser", email="other@example.com")

        response = self.client.post(REGISTER_URL, self.payload(), format="json")

        self.assertEqual(response.status_code, 400)
        self.assertIn("username", response.data)
        self.assertEqual(User.objects.filter(username="newuser").count(), 1)

    def test_invalid_email_is_rejected(self):
        response = self.client.post(
            REGISTER_URL, self.payload(email="not-an-email"), format="json"
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("email", response.data)

    def test_required_fields_are_enforced(self):
        response = self.client.post(REGISTER_URL, {}, format="json")

        self.assertEqual(response.status_code, 400)
        for field in ("username", "email", "password", "password_confirm"):
            self.assertIn(field, response.data)


class TokenTests(ThrottleIsolationMixin, FirestoreTestMixin, APITestCase):
    collections_to_purge = ["user_profiles"]

    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(
            username="owner-a", password=STRONG_PASSWORD
        )

    def obtain(self):
        return self.client.post(
            TOKEN_URL, {"username": "owner-a", "password": STRONG_PASSWORD}
        ).data

    def test_unknown_username_is_401(self):
        response = self.client.post(
            TOKEN_URL, {"username": "nobody", "password": STRONG_PASSWORD}
        )

        self.assertEqual(response.status_code, 401)
        self.assertNotIn("access", response.data)

    def test_inactive_user_cannot_obtain_tokens(self):
        self.user.is_active = False
        self.user.save()

        response = self.client.post(
            TOKEN_URL, {"username": "owner-a", "password": STRONG_PASSWORD}
        )

        self.assertEqual(response.status_code, 401)

    def test_missing_credentials_are_400(self):
        response = self.client.post(TOKEN_URL, {})

        self.assertEqual(response.status_code, 400)
        self.assertIn("username", response.data)
        self.assertIn("password", response.data)

    def test_refresh_rotates_refresh_token(self):
        tokens = self.obtain()

        response = self.client.post(REFRESH_URL, {"refresh": tokens["refresh"]})

        self.assertEqual(response.status_code, 200)
        # ROTATE_REFRESH_TOKENS: the client is handed a fresh refresh token.
        self.assertIn("refresh", response.data)
        self.assertNotEqual(response.data["refresh"], tokens["refresh"])

        follow_up = self.client.post(REFRESH_URL, {"refresh": response.data["refresh"]})
        self.assertEqual(follow_up.status_code, 200)

    def test_refreshed_access_token_authenticates(self):
        tokens = self.obtain()
        access = self.client.post(REFRESH_URL, {"refresh": tokens["refresh"]}).data[
            "access"
        ]

        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        response = self.client.get(PROFILE_URL)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["username"], "owner-a")

    def test_access_token_cannot_be_used_as_refresh(self):
        tokens = self.obtain()

        response = self.client.post(REFRESH_URL, {"refresh": tokens["access"]})

        self.assertEqual(response.status_code, 401)

    def test_garbage_refresh_token_is_401(self):
        response = self.client.post(REFRESH_URL, {"refresh": "not-a-token"})

        self.assertEqual(response.status_code, 401)

    def test_missing_refresh_token_is_400(self):
        response = self.client.post(REFRESH_URL, {})

        self.assertEqual(response.status_code, 400)
        self.assertIn("refresh", response.data)


class PasswordResetTests(ThrottleIsolationMixin, APITestCase):
    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(
            username="owner-a", email="a@example.com", password=STRONG_PASSWORD
        )

    def confirm(self, **overrides):
        data = {
            "user_id": self.user.pk,
            "token": default_token_generator.make_token(self.user),
            "password": NEW_PASSWORD,
            "password_confirm": NEW_PASSWORD,
        }
        data.update(overrides)
        return self.client.post(RESET_CONFIRM_URL, data, format="json")

    def test_request_for_known_email_issues_usable_token(self):
        response = self.client.post(RESET_URL, {"email": "a@example.com"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["message"], "Password reset email sent.")
        self.assertEqual(response.data["user_id"], self.user.pk)
        self.assertTrue(
            default_token_generator.check_token(self.user, response.data["token"])
        )

    def test_request_for_unknown_email_does_not_reveal_absence(self):
        response = self.client.post(RESET_URL, {"email": "nobody@example.com"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, {"message": "Password reset email sent."})

    def test_request_for_shared_email_is_generic(self):
        # Several accounts can share an address; the reset must not 500, pick
        # one arbitrarily, or reveal that duplicates exist.
        User.objects.create_user(username="owner-b", email="a@example.com")

        response = self.client.post(RESET_URL, {"email": "a@example.com"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, {"message": "Password reset email sent."})

    def test_request_requires_valid_email(self):
        response = self.client.post(RESET_URL, {"email": "nope"})

        self.assertEqual(response.status_code, 400)
        self.assertIn("email", response.data)

    def test_full_reset_flow_changes_password(self):
        issued = self.client.post(RESET_URL, {"email": "a@example.com"}).data

        response = self.confirm(user_id=issued["user_id"], token=issued["token"])

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.data, {"message": "Password has been reset successfully."}
        )
        login_new = self.client.post(
            TOKEN_URL, {"username": "owner-a", "password": NEW_PASSWORD}
        )
        login_old = self.client.post(
            TOKEN_URL, {"username": "owner-a", "password": STRONG_PASSWORD}
        )
        self.assertEqual(login_new.status_code, 200)
        self.assertEqual(login_old.status_code, 401)

    def test_token_is_single_use(self):
        token = default_token_generator.make_token(self.user)
        self.assertEqual(self.confirm(token=token).status_code, 200)

        # The token hashes the old password, so changing it invalidates it.
        response = self.confirm(
            token=token, password=STRONG_PASSWORD, password_confirm=STRONG_PASSWORD
        )

        self.assertEqual(response.status_code, 400)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(NEW_PASSWORD))

    def test_bad_token_is_rejected(self):
        response = self.confirm(token="bogus-token")

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data, {"error": "Invalid or expired token."})
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(STRONG_PASSWORD))

    def test_token_for_another_user_is_rejected(self):
        other = User.objects.create_user(username="owner-b", password="pw12345!")

        response = self.confirm(token=default_token_generator.make_token(other))

        self.assertEqual(response.status_code, 400)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(STRONG_PASSWORD))

    def test_unknown_user_id_is_rejected(self):
        response = self.confirm(user_id=999999)

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data, {"error": "Invalid request."})

    def test_missing_user_id_is_rejected(self):
        response = self.client.post(
            RESET_CONFIRM_URL,
            {
                "token": default_token_generator.make_token(self.user),
                "password": NEW_PASSWORD,
                "password_confirm": NEW_PASSWORD,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data, {"error": "Invalid request."})

    def test_mismatched_passwords_are_rejected(self):
        response = self.confirm(password_confirm="Something-Else-42")

        self.assertEqual(response.status_code, 400)
        self.assertIn("password", response.data)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(STRONG_PASSWORD))

    def test_weak_new_password_is_rejected(self):
        response = self.confirm(password="password", password_confirm="password")

        self.assertEqual(response.status_code, 400)
        self.assertIn("password", response.data)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(STRONG_PASSWORD))

    def test_malformed_user_id_is_rejected(self):
        for user_id in ("abc", [self.user.pk], {"id": self.user.pk}, 2**70):
            with self.subTest(user_id=user_id):
                response = self.confirm(user_id=user_id)

                self.assertEqual(response.status_code, 400)
                self.assertEqual(response.data, {"error": "Invalid request."})
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(STRONG_PASSWORD))
