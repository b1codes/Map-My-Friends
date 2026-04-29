from django.conf import settings
from django.contrib.gis.db import models


class Trip(models.Model):
    class Status(models.TextChoices):
        DRAFT = 'DRAFT', 'Draft'
        BOOKED = 'BOOKED', 'Booked'
        CANCELLED = 'CANCELLED', 'Cancelled'

    name = models.CharField(max_length=255)
    date = models.DateField()  # Legacy field
    start_date = models.DateField(null=True, blank=True)
    end_date = models.DateField(null=True, blank=True)
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
        
        # Sync start_date/end_date with legacy date if not set
        if not self.start_date:
            self.start_date = self.date
        if not self.end_date:
            self.end_date = self.date
            
        super().save(*args, **kwargs)

    def _create_stops_snapshots(self):
        for stop in self.stops.all():
            stop.perform_snapshot()

    def generate_legs(self):
        stops = list(self.stops.all().order_by('sequence_order'))
        # Simple sync: Create missing legs
        # We don't delete here to avoid losing data on every save, 
        # but in a reorder/delete stops scenario we might need to.
        # For the prototype, we'll just ensure legs exist between all stops.
        for i in range(len(stops) - 1):
            TripLeg.objects.get_or_create(
                trip=self,
                departure_stop=stops[i],
                arrival_stop=stops[i+1]
            )

    def __str__(self):
        return f"{self.name} ({self.start_date} to {self.end_date}) - {self.get_status_display()}"


class TripStop(models.Model):
    # ... (existing TripStop code)
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
        # ... (existing perform_snapshot code)
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

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        self.trip.generate_legs()


class TripLeg(models.Model):
    class TransportType(models.TextChoices):
        FLIGHT = 'FLIGHT', 'Flight'
        TRAIN = 'TRAIN', 'Train'
        BUS = 'BUS', 'Bus'
        CAR = 'CAR', 'Car'

    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name='legs')
    departure_stop = models.ForeignKey(TripStop, on_delete=models.CASCADE, related_name='departure_legs')
    arrival_stop = models.ForeignKey(TripStop, on_delete=models.CASCADE, related_name='arrival_legs')
    departure_time = models.DateTimeField(null=True, blank=True)
    arrival_time = models.DateTimeField(null=True, blank=True)
    transport_type = models.CharField(
        max_length=20,
        choices=TransportType.choices,
        default=TransportType.CAR,
    )
    booking_reference = models.CharField(max_length=100, blank=True)
    ticket_data = models.JSONField(default=dict, blank=True)

    def __str__(self):
        return f"Leg: {self.departure_stop} -> {self.arrival_stop}"

