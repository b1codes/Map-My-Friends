from rest_framework import serializers
from django.contrib.auth.models import User
from django.contrib.auth.password_validation import validate_password
from .models import UserProfile


class UserProfileSerializer(serializers.ModelSerializer):
    """Serializer for user profile with image upload support."""
    username = serializers.CharField(source='user.username', read_only=True)
    email = serializers.EmailField(source='user.email', read_only=True)
    first_name = serializers.CharField(source='user.first_name', required=False, allow_blank=True)
    last_name = serializers.CharField(source='user.last_name', required=False, allow_blank=True)

    class Meta:
        model = UserProfile
        fields = [
            'username',
            'email',
            'first_name',
            'last_name',
            'profile_image',
            'city',
            'state',
            'country',
            'street',
            'birth_date',
            'phone_number',
            'pin_color',
            'pin_style',
            'pin_icon_type',
            'pin_emoji',
        ]
        read_only_fields = ['username', 'email']

    def update(self, instance, validated_data):
        # Extract user data if present
        user_data = validated_data.pop('user', {})
        if 'first_name' in user_data:
            instance.user.first_name = user_data['first_name']
        if 'last_name' in user_data:
            instance.user.last_name = user_data['last_name']
        
        # Save user model if changes were made
        if user_data:
            instance.user.save()

        # Update remaining profile fields
        return super().update(instance, validated_data)


class RegisterSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(required=True)
    password = serializers.CharField(write_only=True, required=True, validators=[validate_password])
    password_confirm = serializers.CharField(write_only=True, required=True)
    first_name = serializers.CharField(required=False, allow_blank=True)
    last_name = serializers.CharField(required=False, allow_blank=True)
    # Honeypot field
    first_name_hp = serializers.CharField(required=False, allow_blank=True, write_only=True)

    class Meta:
        model = User
        fields = ('username', 'email', 'password', 'password_confirm', 'first_name', 'last_name', 'first_name_hp')

    def validate(self, attrs):
        if attrs.get('first_name_hp'):
            # If honeypot is filled, it's a bot.
            # We raise a generic error to not reveal it's a honeypot.
            raise serializers.ValidationError({"detail": "Invalid request."})

        if attrs['password'] != attrs['password_confirm']:
            raise serializers.ValidationError({"password": "Passwords do not match."})
        
        if User.objects.filter(email=attrs['email']).exists():
            raise serializers.ValidationError({"email": "A user with this email already exists."})
        
        return attrs

    def create(self, validated_data):
        validated_data.pop('password_confirm')
        validated_data.pop('first_name_hp', None)
        user = User.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            password=validated_data['password'],
            first_name=validated_data.get('first_name', ''),
            last_name=validated_data.get('last_name', ''),
        )
        return user


class PasswordResetRequestSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)


class PasswordResetConfirmSerializer(serializers.Serializer):
    token = serializers.CharField(required=True)
    password = serializers.CharField(write_only=True, required=True, validators=[validate_password])
    password_confirm = serializers.CharField(write_only=True, required=True)

    def validate(self, attrs):
        if attrs['password'] != attrs['password_confirm']:
            raise serializers.ValidationError({"password": "Passwords do not match."})
        return attrs
