from django.contrib.auth.models import AnonymousUser, User
from django.test import TestCase
from rest_framework.test import APIRequestFactory

from apps.users.repositories import UserProfileRecord
from apps.users.serializers import (
    PasswordResetConfirmSerializer,
    RegisterSerializer,
    UserProfileSerializer,
)

STRONG_PASSWORD = "Tr1cky-Horse-Battery"


def request_for(user):
    request = APIRequestFactory().get("/api/user/profile/")
    request.user = user
    return request


class UserProfileSerializerTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="owner-a", email="a@example.com", first_name="Ada"
        )
        self.record = UserProfileRecord(owner_key="owner-a", city="London")

    def test_account_fields_come_from_request_user(self):
        data = UserProfileSerializer(
            self.record, context={"request": request_for(self.user)}
        ).data

        self.assertEqual(data["username"], "owner-a")
        self.assertEqual(data["email"], "a@example.com")
        self.assertEqual(data["first_name"], "Ada")
        self.assertEqual(data["last_name"], "")
        self.assertEqual(data["city"], "London")

    def test_anonymous_request_exposes_no_account_fields(self):
        data = UserProfileSerializer(
            self.record, context={"request": request_for(AnonymousUser())}
        ).data

        self.assertIsNone(data["username"])
        self.assertIsNone(data["email"])
        # The profile record has no name attributes, so without a user they
        # are omitted rather than leaked from anywhere else.
        self.assertNotIn("first_name", data)
        self.assertNotIn("last_name", data)
        self.assertEqual(data["city"], "London")

    def test_missing_request_context_is_tolerated(self):
        data = UserProfileSerializer(self.record).data

        self.assertIsNone(data["username"])
        self.assertIsNone(data["profile_image"])

    def test_profile_image_is_absolute_with_request(self):
        self.record.profile_image = "user_profiles/abc.png"

        data = UserProfileSerializer(
            self.record, context={"request": request_for(self.user)}
        ).data

        self.assertEqual(
            data["profile_image"], "http://testserver/media/user_profiles/abc.png"
        )

    def test_profile_image_is_relative_without_request(self):
        self.record.profile_image = "user_profiles/abc.png"

        data = UserProfileSerializer(self.record).data

        self.assertEqual(data["profile_image"], "/media/user_profiles/abc.png")

    def test_account_identity_fields_are_read_only(self):
        serializer = UserProfileSerializer(
            data={"username": "hijack", "email": "x@example.com", "city": "Paris"},
            partial=True,
        )

        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertEqual(dict(serializer.validated_data), {"city": "Paris"})

    def test_pin_emoji_accepts_null_and_blank(self):
        for value in (None, ""):
            serializer = UserProfileSerializer(data={"pin_emoji": value}, partial=True)
            self.assertTrue(serializer.is_valid(), serializer.errors)


class RegisterSerializerTests(TestCase):
    def data(self, **overrides):
        data = {
            "username": "newuser",
            "email": "new@example.com",
            "password": STRONG_PASSWORD,
            "password_confirm": STRONG_PASSWORD,
        }
        data.update(overrides)
        return data

    def test_honeypot_fails_with_generic_error(self):
        serializer = RegisterSerializer(data=self.data(first_name_hp="bot"))

        self.assertFalse(serializer.is_valid())
        # The error must not name the honeypot field.
        self.assertNotIn("first_name_hp", serializer.errors)
        self.assertEqual(str(serializer.errors["detail"][0]), "Invalid request.")

    def test_mismatched_passwords_fail(self):
        serializer = RegisterSerializer(
            data=self.data(password_confirm="Something-Else-42")
        )

        self.assertFalse(serializer.is_valid())
        self.assertEqual(
            str(serializer.errors["password"][0]), "Passwords do not match."
        )

    def test_too_short_password_fails(self):
        serializer = RegisterSerializer(
            data=self.data(password="short", password_confirm="short")
        )

        self.assertFalse(serializer.is_valid())
        self.assertIn("password", serializer.errors)

    def test_create_strips_write_only_helpers(self):
        serializer = RegisterSerializer(data=self.data(first_name_hp=""))
        self.assertTrue(serializer.is_valid(), serializer.errors)

        user = serializer.save()

        self.assertTrue(user.check_password(STRONG_PASSWORD))
        self.assertEqual(user.first_name, "")
        self.assertEqual(user.last_name, "")


class PasswordResetConfirmSerializerTests(TestCase):
    def test_matching_passwords_pass(self):
        serializer = PasswordResetConfirmSerializer(
            data={
                "token": "t",
                "password": STRONG_PASSWORD,
                "password_confirm": STRONG_PASSWORD,
            }
        )

        self.assertTrue(serializer.is_valid(), serializer.errors)

    def test_mismatched_passwords_fail(self):
        serializer = PasswordResetConfirmSerializer(
            data={
                "token": "t",
                "password": STRONG_PASSWORD,
                "password_confirm": "Something-Else-42",
            }
        )

        self.assertFalse(serializer.is_valid())
        self.assertEqual(
            str(serializer.errors["password"][0]), "Passwords do not match."
        )

    def test_token_is_required(self):
        serializer = PasswordResetConfirmSerializer(
            data={"password": STRONG_PASSWORD, "password_confirm": STRONG_PASSWORD}
        )

        self.assertFalse(serializer.is_valid())
        self.assertIn("token", serializer.errors)
