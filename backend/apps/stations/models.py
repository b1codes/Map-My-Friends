from django.contrib.gis.db import models


class Station(models.Model):
    name = models.CharField(max_length=255)
    osm_id = models.BigIntegerField(unique=True)
    station_type = models.CharField(max_length=100, blank=True)
    uic_ref = models.CharField(max_length=100, blank=True)
    city = models.CharField(max_length=255, blank=True)
    country = models.CharField(max_length=100, blank=True)
    location = models.PointField(srid=4326)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return f"{self.name} ({self.osm_id})"
