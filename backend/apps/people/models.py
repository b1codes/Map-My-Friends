from django.contrib.gis.db import models
from phonenumber_field.modelfields import PhoneNumberField
from django.utils.translation import gettext_lazy as _


class Person(models.Model):
    TAG_CHOICES = [
        ('FRIEND', _('Friend')),
        ('FAMILY', _('Family')),
    ]

    tag = models.CharField(max_length=10, choices=TAG_CHOICES)
    
    first_name = models.CharField(max_length=100, default="")
    last_name = models.CharField(max_length=100, default="")
    
    city = models.CharField(max_length=100, default="")
    state = models.CharField(max_length=100, default="")
    country = models.CharField(max_length=100, default="")
    street = models.CharField(max_length=255, blank=True, null=True)
    
    birthday = models.DateField(blank=True, null=True)
    phone_number = PhoneNumberField(blank=True, null=True)
    
    profile_image = models.ImageField(upload_to='profile_images/', blank=True, null=True)
    
    location = models.PointField()
    timezone = models.CharField(max_length=50, blank=True, null=True)

    pin_color = models.CharField(max_length=20, default='#F44336')
    
    PIN_STYLE_CHOICES = [
        ('teardrop', _('Teardrop')),
        ('circle', _('Circle')),
        ('square', _('Square')),
        ('triangle', _('Triangle')),
        ('diamond', _('Diamond')),
    ]
    pin_style = models.CharField(max_length=20, choices=PIN_STYLE_CHOICES, default='teardrop')
    
    PIN_ICON_TYPE_CHOICES = [
        ('none', _('None')),
        ('emoji', _('Emoji')),
        ('initials', _('Initials')),
        ('picture', _('Picture')),
    ]
    pin_icon_type = models.CharField(max_length=20, choices=PIN_ICON_TYPE_CHOICES, default='none')
    
    pin_emoji = models.CharField(max_length=10, blank=True, null=True)

    def save(self, *args, **kwargs):
        if not self.location:
            from geopy.geocoders import Nominatim
            from geopy.exc import GeocoderTimedOut, GeocoderServiceError
            from django.contrib.gis.geos import Point
            from django.core.exceptions import ValidationError
            import time
            from timezonefinder import TimezoneFinder

            geolocator = Nominatim(user_agent="map_my_friends_global_connect")
            tf = TimezoneFinder()
            
            # Structured query for better international accuracy
            query = {
                'city': self.city,
                'state': self.state,
                'country': self.country,
            }
            if self.street:
                query['street'] = self.street

            for attempt in range(3):
                try:
                    location = geolocator.geocode(query)
                    if location:
                        self.location = Point(location.longitude, location.latitude)
                        self.timezone = tf.timezone_at(lng=location.longitude, lat=location.latitude)
                        break
                except (GeocoderTimedOut, GeocoderServiceError):
                    if attempt < 2:
                        time.sleep(1)
                    else:
                        raise ValidationError(_("Geocoding service unavailable. Please try again later."))
            else:
                if not self.location:
                    address_str = f"{self.street or ''}, {self.city}, {self.state}, {self.country}".strip(", ")
                    raise ValidationError(_("Could not geocode address: %(address)s") % {'address': address_str})

        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.first_name} {self.last_name} ({self.tag})"
