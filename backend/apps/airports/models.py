from django.contrib.gis.db import models
from django.utils.translation import gettext_lazy as _


class Airport(models.Model):
    AIRPORT_TYPE_CHOICES = [
        ('large_airport', _('Large Airport')),
        ('medium_airport', _('Medium Airport')),
    ]

    name = models.CharField(max_length=255)
    iata_code = models.CharField(max_length=3, unique=True)
    icao_code = models.CharField(max_length=4, blank=True, null=True)
    airport_type = models.CharField(max_length=20, choices=AIRPORT_TYPE_CHOICES)
    city = models.CharField(max_length=255, blank=True, default='')
    country = models.CharField(max_length=10, help_text="ISO country code")
    continent = models.CharField(max_length=2, blank=True, default='')
    location = models.PointField()

    class Meta:
        ordering = ['name']

    def __str__(self):
        return f"{self.name} ({self.iata_code})"
