from django.conf import settings
from django.contrib.gis.db import models


class Trip(models.Model):
    class Status(models.TextChoices):
        DRAFT = 'DRAFT', 'Draft'
        BOOKED = 'BOOKED', 'Booked'
        CANCELLED = 'CANCELLED', 'Cancelled'

    name = models.CharField(max_length=255)
    date = models.DateField()
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='trips',
    )
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.DRAFT,
    )

    def __str__(self):
        return f"{self.name} ({self.date}) - {self.get_status_display()}"


class TripStop(models.Model):
    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name='stops')
    person = models.ForeignKey('people.Person', on_delete=models.SET_NULL, null=True)
    sequence_order = models.PositiveIntegerField()
    location = models.PointField()

    class Meta:
        ordering = ['sequence_order']
        unique_together = [('trip', 'sequence_order')]

    def __str__(self):
        return f"Stop {self.sequence_order} on {self.trip}"
