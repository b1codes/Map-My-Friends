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
            stop.perform_snapshot()

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

    def perform_snapshot(self):
        metadata = {
            'people': [],
            'hub': None
        }
        address_parts = []

        # Snapshot People
        for person in self.people.all():
            metadata['people'].append({
                'id': person.id,
                'name': f"{person.first_name} {person.last_name}",
            })
            person_addr = ", ".join(filter(None, [
                f"{person.first_name} {person.last_name}",
                person.street,
                person.city,
                person.state,
                person.country
            ]))
            address_parts.append(person_addr)

        # Snapshot Hub (Airport or Station)
        if self.airport:
            metadata['hub'] = {
                'name': self.airport.name,
                'code': self.airport.iata_code,
                'type': 'AIRPORT'
            }
            address_parts.append(f"{self.airport.name} ({self.airport.iata_code})")
        elif self.station:
            metadata['hub'] = {
                'name': self.station.name,
                'code': self.station.uic_ref or str(self.station.osm_id),
                'type': 'STATION'
            }
            address_parts.append(self.station.name)

        self.snapshot_address = ", ".join(address_parts)
        self.snapshot_metadata = metadata
        self.save()

    def __str__(self):
        return f"Stop {self.sequence_order} on {self.trip}"

