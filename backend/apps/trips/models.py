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

    def save(self, *args, **kwargs):
        is_new = self.pk is None
        if not is_new:
            old_instance = Trip.objects.get(pk=self.pk)
            if old_instance.status == self.Status.DRAFT and self.status == self.Status.BOOKED:
                self._create_stops_snapshots()
        super().save(*args, **kwargs)

    def _create_stops_snapshots(self):
        for stop in self.stops.all():
            metadata = {
                'people': [],
                'airport': None,
                'station': None
            }
            address_parts = []

            # Snapshot People
            for person in stop.people.all():
                metadata['people'].append({
                    'id': person.id,
                    'first_name': person.first_name,
                    'last_name': person.last_name,
                    'city': person.city,
                    'state': person.state,
                    'country': person.country,
                    'street': person.street,
                })
                person_addr = ", ".join(filter(None, [f"{person.first_name} {person.last_name}", person.street, person.city, person.state, person.country]))
                address_parts.append(person_addr)

            # Snapshot Airport
            if stop.airport:
                metadata['airport'] = {
                    'id': stop.airport.id,
                    'name': stop.airport.name,
                    'iata_code': stop.airport.iata_code,
                    'city': stop.airport.city,
                    'country': stop.airport.country,
                }
                address_parts.append(f"{stop.airport.name} ({stop.airport.iata_code})")

            # Snapshot Station
            if stop.station:
                metadata['station'] = {
                    'id': stop.station.id,
                    'name': stop.station.name,
                    'city': stop.station.city,
                    'country': stop.station.country,
                }
                address_parts.append(stop.station.name)

            stop.snapshot_address = ", ".join(address_parts)
            stop.snapshot_metadata = metadata
            stop.save()

    def __str__(self):
        return f"{self.name} ({self.date}) - {self.get_status_display()}"


class TripStop(models.Model):
    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name='stops')
    people = models.ManyToManyField('people.Person', blank=True)
    airport = models.ForeignKey('airports.Airport', on_delete=models.SET_NULL, null=True, blank=True)
    station = models.ForeignKey('stations.Station', on_delete=models.SET_NULL, null=True, blank=True)
    sequence_order = models.PositiveIntegerField()
    location = models.PointField()
    snapshot_address = models.CharField(max_length=500, blank=True)
    snapshot_metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ['sequence_order']
        unique_together = [('trip', 'sequence_order')]

    def __str__(self):
        return f"Stop {self.sequence_order} on {self.trip}"
