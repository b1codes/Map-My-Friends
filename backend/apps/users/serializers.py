from django.contrib.auth.models import User
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.serializers import TokenRefreshSerializer
from rest_framework_simplejwt.settings import api_settings
from rest_framework_simplejwt.tokens import RefreshToken

from apps.common import firestore as fs
from apps.common.fields import PinColorField


def validate_password_for(password, user):
    """Django's password validators, run against `user`, as a DRF error.

    Passing the user matters: UserAttributeSimilarityValidator compares the
    password with the username, email and names, and with no user it passes
    everything. Used as a bare field validator, that's what happened.
    """
    try:
        validate_password(password, user=user)
    except DjangoValidationError as e:
        raise serializers.ValidationError({"password": list(e.messages)}) from e


class UserProfileSerializer(serializers.Serializer):
    # username/email/first_name/last_name live on the Django User, not on the
    # Firestore profile document, so they are resolved from the request user.
    # They were part of this endpoint's contract before the migration:
    # frontend/lib/services/auth_service.dart sends first_name/last_name on
    # update, and dropping them would silently stop name edits from saving.
    username = serializers.SerializerMethodField()
    email = serializers.SerializerMethodField()
    first_name = serializers.CharField(required=False, allow_blank=True)
    last_name = serializers.CharField(required=False, allow_blank=True)
    profile_image = serializers.SerializerMethodField()
    city = serializers.CharField(max_length=100, required=False, allow_blank=True)
    state = serializers.CharField(max_length=100, required=False, allow_blank=True)
    country = serializers.CharField(max_length=100, required=False, allow_blank=True)
    street = serializers.CharField(max_length=255, required=False, allow_blank=True)
    birth_date = serializers.DateField(required=False, allow_null=True)
    phone_number = serializers.CharField(required=False, allow_blank=True)
    pin_color = PinColorField(required=False)
    pin_style = serializers.ChoiceField(
        choices=["teardrop", "circle", "square", "triangle", "diamond"], required=False
    )
    pin_icon_type = serializers.ChoiceField(
        choices=["none", "emoji", "initials", "picture"], required=False
    )
    pin_emoji = serializers.CharField(
        max_length=10, required=False, allow_null=True, allow_blank=True
    )
    distance_unit = serializers.ChoiceField(
        choices=["metric", "imperial"], required=False
    )

    def _request_user(self):
        request = self.context.get("request")
        return getattr(request, "user", None)

    def get_username(self, obj):
        user = self._request_user()
        return user.username if user and user.is_authenticated else None

    def get_email(self, obj):
        user = self._request_user()
        return user.email if user and user.is_authenticated else None

    def to_representation(self, instance):
        ret = super().to_representation(instance)
        user = self._request_user()
        # first_name/last_name are declared writable, so they are not
        # SerializerMethodFields; fill them from the User on the way out.
        if user and user.is_authenticated:
            ret["first_name"] = user.first_name
            ret["last_name"] = user.last_name
        return ret

    def get_profile_image(self, obj):
        from apps.common.storage import upload_url

        return upload_url(
            getattr(obj, "profile_image", None), self.context.get("request")
        )


class RegisterSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(required=True)
    # Checked against the new user's details in validate().
    password = serializers.CharField(write_only=True, required=True)
    password_confirm = serializers.CharField(write_only=True, required=True)
    first_name = serializers.CharField(required=False, allow_blank=True)
    last_name = serializers.CharField(required=False, allow_blank=True)
    # Honeypot field
    first_name_hp = serializers.CharField(
        required=False, allow_blank=True, write_only=True
    )

    class Meta:
        model = User
        fields = (
            "username",
            "email",
            "password",
            "password_confirm",
            "first_name",
            "last_name",
            "first_name_hp",
        )

    def validate_username(self, value):
        # The username names the account's profile document. Django's
        # validator allows ".", ".." and "__x__", which Firestore refuses as
        # document ids, so such an account could never load its profile.
        if not fs.is_valid_doc_id(value):
            raise serializers.ValidationError(
                'This username can\'t be used. Usernames can\'t be "." or "..", '
                'or begin and end with "__".'
            )
        return value

    def validate(self, attrs):
        if attrs.get("first_name_hp"):
            # If honeypot is filled, it's a bot.
            # We raise a generic error to not reveal it's a honeypot.
            raise serializers.ValidationError({"detail": "Invalid request."})

        if attrs["password"] != attrs["password_confirm"]:
            raise serializers.ValidationError({"password": "Passwords do not match."})

        if User.objects.filter(email=attrs["email"]).exists():
            raise serializers.ValidationError(
                {"email": "A user with this email already exists."}
            )

        validate_password_for(
            attrs["password"],
            User(
                username=attrs["username"],
                email=attrs["email"],
                first_name=attrs.get("first_name", ""),
                last_name=attrs.get("last_name", ""),
            ),
        )
        return attrs

    def create(self, validated_data):
        validated_data.pop("password_confirm")
        validated_data.pop("first_name_hp", None)
        return User.objects.create_user(
            username=validated_data["username"],
            email=validated_data["email"],
            password=validated_data["password"],
            first_name=validated_data.get("first_name", ""),
            last_name=validated_data.get("last_name", ""),
        )


class PasswordResetRequestSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)


class PasswordResetConfirmSerializer(serializers.Serializer):
    token = serializers.CharField(required=True)
    # Checked against the account in PasswordResetConfirmView, the first point
    # that knows which user it is.
    password = serializers.CharField(write_only=True, required=True)
    password_confirm = serializers.CharField(write_only=True, required=True)

    def validate(self, attrs):
        if attrs["password"] != attrs["password_confirm"]:
            raise serializers.ValidationError({"password": "Passwords do not match."})
        return attrs


class UserNamingRefreshToken(RefreshToken):
    """A refresh token that must name its user (USER_ID_CLAIM).

    Refresh tokens issued before tokens named the user by username carry only
    user_id. SimpleJWT's refresh skips its user check when the claim is
    missing and mints an access token without it, which every request then
    refuses with a 401: the client refreshes again, and loops. Failing
    verification makes the refresh itself a 401, so the client signs out,
    and no access token is ever minted from such a token.
    """

    def verify(self, *args, **kwargs):
        super().verify(*args, **kwargs)
        if not self.payload.get(api_settings.USER_ID_CLAIM):
            raise TokenError("Token contained no recognizable user identification")


class MissingUserTokenRefreshSerializer(TokenRefreshSerializer):
    """SimpleJWT's refresh, with a 401 when the token's user isn't here.

    SimpleJWT looks the user up with objects.get() and lets DoesNotExist
    escape as a 500. Until GCIP, that is every refresh served by an instance
    other than the one the user signed up on. A token that names no user at
    all is refused too (UserNamingRefreshToken).
    """

    token_class = UserNamingRefreshToken

    def validate(self, attrs):
        try:
            return super().validate(attrs)
        except User.DoesNotExist as e:
            raise AuthenticationFailed(
                self.error_messages["no_active_account"], "no_active_account"
            ) from e
