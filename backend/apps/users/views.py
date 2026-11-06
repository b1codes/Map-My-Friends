from django.contrib.auth.models import User
from django.contrib.auth.tokens import default_token_generator
from rest_framework import generics, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.ownership import owner_key_for

from .serializers import (
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
    RegisterSerializer,
    UserProfileSerializer,
)
from .throttles import BurstAnonRateThrottle, SustainedAnonRateThrottle


class UserProfileView(APIView):
    """Get and update the current user's profile.

    Supports image upload via multipart form data.
    """

    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    @property
    def repository(self):
        from .repositories import UserProfileRepository

        return UserProfileRepository()

    def get(self, request):
        profile = self.repository.get_or_create(owner_key_for(request))
        return Response(
            UserProfileSerializer(profile, context={"request": request}).data
        )

    def patch(self, request):
        serializer = UserProfileSerializer(
            data=request.data, partial=True, context={"request": request}
        )
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        payload = dict(serializer.validated_data)
        birth_date = payload.get("birth_date")
        if birth_date is not None:
            payload["birth_date"] = birth_date.isoformat()

        # first_name/last_name belong to the Django User, not the Firestore
        # profile document. The old ModelSerializer.update() wrote them back
        # via source='user.*'; with a plain Serializer that has to be explicit,
        # or name-only edits silently no-op (and used to 500 on an empty
        # Firestore update).
        user_fields = {
            field: payload.pop(field)
            for field in ("first_name", "last_name")
            if field in payload
        }
        if user_fields:
            for field, value in user_fields.items():
                setattr(request.user, field, value)
            request.user.save(update_fields=list(user_fields))

        uploaded = request.FILES.get("profile_image")
        if uploaded is not None:
            from apps.common.storage import save_upload

            payload["profile_image"] = save_upload(uploaded, prefix="user_profiles")

        profile = self.repository.update(owner_key_for(request), payload)
        return Response(
            UserProfileSerializer(profile, context={"request": request}).data
        )


class RegisterView(generics.CreateAPIView):
    """Register a new user."""

    queryset = User.objects.all()
    permission_classes = [AllowAny]
    serializer_class = RegisterSerializer
    throttle_classes = [BurstAnonRateThrottle, SustainedAnonRateThrottle]


class PasswordResetRequestView(generics.GenericAPIView):
    """Request a password reset email."""

    serializer_class = PasswordResetRequestSerializer
    permission_classes = [AllowAny]
    # Restrict password reset requests to prevent spam
    throttle_classes = [BurstAnonRateThrottle, SustainedAnonRateThrottle]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        # The token and user_id are what PasswordResetConfirmView takes, so
        # they may only ever reach the address's inbox, never this response:
        # returning them let anyone who knew an email reset that account's
        # password. No email is sent yet, so a reset can't be completed; the
        # response is the same for every address so it doesn't reveal which
        # ones have accounts.
        return Response(
            {"message": "Password reset email sent."},
            status=status.HTTP_200_OK,
        )


class PasswordResetConfirmView(generics.GenericAPIView):
    """Confirm password reset with token and new password."""

    serializer_class = PasswordResetConfirmSerializer
    permission_classes = [AllowAny]
    throttle_classes = [BurstAnonRateThrottle]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        token = serializer.validated_data["token"]
        password = serializer.validated_data["password"]
        user_id = request.data.get("user_id")

        try:
            user = User.objects.get(pk=user_id)
            if default_token_generator.check_token(user, token):
                user.set_password(password)
                user.save()
                return Response(
                    {"message": "Password has been reset successfully."},
                    status=status.HTTP_200_OK,
                )
            else:
                return Response(
                    {"error": "Invalid or expired token."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
        except User.DoesNotExist:
            return Response(
                {"error": "Invalid request."}, status=status.HTTP_400_BAD_REQUEST
            )
