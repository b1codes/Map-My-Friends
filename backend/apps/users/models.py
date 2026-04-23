from django.db import models
from django.contrib.auth.models import User
from django.db.models.signals import post_save
from django.dispatch import receiver
from phonenumber_field.modelfields import PhoneNumberField


class UserProfile(models.Model):
    """Profile for authenticated users with profile picture and address."""
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    profile_image = models.ImageField(upload_to='user_profiles/', blank=True, null=True)
    city = models.CharField(max_length=100, blank=True, default='')
    state = models.CharField(max_length=100, blank=True, default='')
    country = models.CharField(max_length=100, blank=True, default='')
    street = models.CharField(max_length=255, blank=True, default='')
    birth_date = models.DateField(blank=True, null=True)
    phone_number = PhoneNumberField(blank=True, default='')

    # Map Pin Customization
    PIN_STYLE_CHOICES = [
        ('teardrop', 'Teardrop'),
        ('circle', 'Circle'),
        ('square', 'Square'),
        ('triangle', 'Triangle'),
        ('diamond', 'Diamond'),
    ]
    
    PIN_ICON_TYPE_CHOICES = [
        ('none', 'None'),
        ('emoji', 'Emoji'),
        ('initials', 'Initials'),
        ('picture', 'Profile Picture'),
    ]

    pin_color = models.CharField(max_length=7, default='#2196F3', help_text="Hex color code for the map pin")
    pin_style = models.CharField(max_length=20, choices=PIN_STYLE_CHOICES, default='teardrop', help_text="Shape of the map pin")
    pin_icon_type = models.CharField(max_length=20, choices=PIN_ICON_TYPE_CHOICES, default='none', help_text="What to display inside the pin")
    pin_emoji = models.CharField(max_length=10, blank=True, null=True, help_text="Emoji to display if icon_type is 'emoji'")

    def __str__(self):
        return f"Profile for {self.user.username}"


@receiver(post_save, sender=User)
def create_user_profile(sender, instance, created, **kwargs):
    """Auto-create UserProfile when a User is created."""
    if created:
        UserProfile.objects.create(user=instance)


@receiver(post_save, sender=User)
def save_user_profile(sender, instance, **kwargs):
    """Auto-save UserProfile when User is saved."""
    if hasattr(instance, 'profile'):
        instance.profile.save()
