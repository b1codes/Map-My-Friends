import datetime
from django.test import TestCase
from django.contrib.auth.models import User
from django.contrib.gis.geos import Point
from apps.people.models import Person
from .models import Trip, TripStop


class TripModelTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='testuser', password='pw')
        self.person = Person.objects.create(
            tag='FRIEND',
            first_name='Jane',
            last_name='Doe',
            city='Chicago',
            state='IL',
            country='US',
            location=Point(-87.6298, 41.8781, srid=4326),
        )

    def test_trip_creation(self):
        trip = Trip.objects.create(
            name='Summer Road Trip',
            date=datetime.date(2026, 7, 4),
            user=self.user,
        )
        self.assertEqual(trip.name, 'Summer Road Trip')
        self.assertEqual(trip.user, self.user)

    def test_tripstop_ordering(self):
        trip = Trip.objects.create(
            name='Test Trip',
            date=datetime.date(2026, 7, 4),
            user=self.user,
        )
        TripStop.objects.create(
            trip=trip,
            person=self.person,
            sequence_order=2,
            location=Point(-73.9857, 40.7484, srid=4326),
        )
        TripStop.objects.create(
            trip=trip,
            person=self.person,
            sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        stops = list(trip.stops.all())
        self.assertEqual(stops[0].sequence_order, 1)
        self.assertEqual(stops[1].sequence_order, 2)

    def test_tripstop_cascade_delete(self):
        trip = Trip.objects.create(
            name='Test Trip',
            date=datetime.date(2026, 7, 4),
            user=self.user,
        )
        TripStop.objects.create(
            trip=trip,
            person=self.person,
            sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        trip_id = trip.id
        trip.delete()
        self.assertFalse(TripStop.objects.filter(trip_id=trip_id).exists())
