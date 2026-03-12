from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser
from rest_framework.views import APIView
from django.contrib.auth.models import User
from django.contrib.auth.tokens import default_token_generator

from .throttles import BurstAnonRateThrottle, SustainedAnonRateThrottle
from .models import UserProfile
from .serializers import (
    UserProfileSerializer,
    RegisterSerializer,
    PasswordResetRequestSerializer,
    PasswordResetConfirmSerializer,
)


class UserProfileView(APIView):
    """
    View for getting and updating the current user's profile.
    Supports image upload via multipart form data.
    """
    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def get(self, request):
        """Get current user's profile."""
        try:
            profile = request.user.profile
        except UserProfile.DoesNotExist:
            profile = UserProfile.objects.create(user=request.user)
            
        serializer = UserProfileSerializer(profile, context={'request': request})
        return Response(serializer.data)

    def patch(self, request):
        """Update the current user's profile (supports partial updates)."""
        profile = request.user.profile
        serializer = UserProfileSerializer(
            profile,
            data=request.data,
            partial=True,
            context={'request': request}
        )
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


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
        
        email = serializer.validated_data['email']
        try:
            user = User.objects.get(email=email)
            token = default_token_generator.make_token(user)
            # In production, send an actual email with the reset link
            # For now, we'll just return the token (development only)
            return Response({
                'message': 'Password reset email sent.',
                'token': token,  # Remove this in production!
                'user_id': user.pk,  # Remove this in production!
            }, status=status.HTTP_200_OK)
        except User.DoesNotExist:
            # Don't reveal whether the email exists
            return Response({
                'message': 'Password reset email sent.',
            }, status=status.HTTP_200_OK)


class PasswordResetConfirmView(generics.GenericAPIView):
    """Confirm password reset with token and new password."""
    serializer_class = PasswordResetConfirmSerializer
    permission_classes = [AllowAny]
    throttle_classes = [BurstAnonRateThrottle]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        
        token = serializer.validated_data['token']
        password = serializer.validated_data['password']
        user_id = request.data.get('user_id')
        
        try:
            user = User.objects.get(pk=user_id)
            if default_token_generator.check_token(user, token):
                user.set_password(password)
                user.save()
                return Response({
                    'message': 'Password has been reset successfully.'
                }, status=status.HTTP_200_OK)
            else:
                return Response({
                    'error': 'Invalid or expired token.'
                }, status=status.HTTP_400_BAD_REQUEST)
        except User.DoesNotExist:
            return Response({
                'error': 'Invalid request.'
            }, status=status.HTTP_400_BAD_REQUEST)
