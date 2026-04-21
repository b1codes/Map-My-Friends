import datetime
from django.test import TestCase
from django.contrib.auth.models import User
from django.contrib.gis.geos import Point
from apps.people.models import Person
from .models import Trip, TripStop
from .serializers import TripSerializer
from rest_framework.test import APIClient


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


class TripSerializerTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='seruser', password='pw')
        self.person = Person.objects.create(
            tag='FRIEND',
            first_name='Alice',
            last_name='Smith',
            city='New York',
            state='NY',
            country='US',
            location=Point(-73.9857, 40.7484, srid=4326),
        )

    def test_serializer_includes_stops_in_order(self):
        trip = Trip.objects.create(
            name='My Trip',
            date=datetime.date(2026, 8, 1),
            user=self.user,
        )
        TripStop.objects.create(
            trip=trip, person=self.person, sequence_order=2,
            location=Point(-73.9857, 40.7484, srid=4326),
        )
        TripStop.objects.create(
            trip=trip, person=self.person, sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        serializer = TripSerializer(trip)
        data = serializer.data
        self.assertEqual(data['name'], 'My Trip')
        self.assertEqual(len(data['stops']), 2)
        self.assertEqual(data['stops'][0]['sequence_order'], 1)
        self.assertEqual(data['stops'][1]['sequence_order'], 2)

    def test_serializer_write_creates_stops(self):
        data = {
            'name': 'New Trip',
            'date': '2026-09-01',
            'stops': [
                {
                    'person': self.person.id,
                    'sequence_order': 1,
                    'location': {'type': 'Point', 'coordinates': [-87.6298, 41.8781]},
                },
            ],
        }
        serializer = TripSerializer(data=data)
        self.assertTrue(serializer.is_valid(), serializer.errors)
        trip = serializer.save(user=self.user)
        self.assertEqual(trip.stops.count(), 1)
        self.assertEqual(trip.stops.first().sequence_order, 1)

    def test_serializer_update_replaces_stops(self):
        trip = Trip.objects.create(
            name='Old Trip',
            date=datetime.date(2026, 8, 1),
            user=self.user,
        )
        TripStop.objects.create(
            trip=trip, person=self.person, sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        data = {
            'name': 'Updated Trip',
            'date': '2026-09-15',
            'stops': [
                {
                    'person': self.person.id,
                    'sequence_order': 1,
                    'location': {'type': 'Point', 'coordinates': [-73.9857, 40.7484]},
                },
                {
                    'person': self.person.id,
                    'sequence_order': 2,
                    'location': {'type': 'Point', 'coordinates': [-87.6298, 41.8781]},
                },
            ],
        }
        serializer = TripSerializer(trip, data=data)
        self.assertTrue(serializer.is_valid(), serializer.errors)
        updated = serializer.save()
        self.assertEqual(updated.name, 'Updated Trip')
        self.assertEqual(updated.stops.count(), 2)

    def test_serializer_update_handles_sequence_order_overlap(self):
        trip = Trip.objects.create(
            name='Overlap Trip',
            date=datetime.date(2026, 8, 1),
            user=self.user,
        )
        TripStop.objects.create(
            trip=trip, person=self.person, sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        TripStop.objects.create(
            trip=trip, person=self.person, sequence_order=2,
            location=Point(-73.9857, 40.7484, srid=4326),
        )
        # Update with stops where sequence_order 2 overlaps with old stop 2 but is a different stop
        data = {
            'name': 'Overlap Trip',
            'date': '2026-08-01',
            'stops': [
                {
                    'person': self.person.id,
                    'sequence_order': 2,
                    'location': {'type': 'Point', 'coordinates': [-87.6298, 41.8781]},
                },
                {
                    'person': self.person.id,
                    'sequence_order': 3,
                    'location': {'type': 'Point', 'coordinates': [-73.9857, 40.7484]},
                },
            ],
        }
        serializer = TripSerializer(trip, data=data)
        self.assertTrue(serializer.is_valid(), serializer.errors)
        updated = serializer.save()
        self.assertEqual(updated.stops.count(), 2)
        orders = list(updated.stops.values_list('sequence_order', flat=True))
        self.assertEqual(orders, [2, 3])


class TripApiTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(username='apiuser', password='pw')
        self.other_user = User.objects.create_user(username='other', password='pw')
        self.client.force_authenticate(user=self.user)
        self.person = Person.objects.create(
            tag='FRIEND',
            first_name='Bob',
            last_name='Jones',
            city='Chicago',
            state='IL',
            country='US',
            location=Point(-87.6298, 41.8781, srid=4326),
        )

    def test_unauthenticated_returns_401(self):
        unauthenticated = APIClient()
        response = unauthenticated.get('/api/trips/')
        self.assertEqual(response.status_code, 401)

    def test_list_returns_only_own_trips(self):
        Trip.objects.create(name='My Trip', date='2026-07-01', user=self.user)
        Trip.objects.create(name='Other Trip', date='2026-07-02', user=self.other_user)
        response = self.client.get('/api/trips/')
        self.assertEqual(response.status_code, 200)
        results = response.data['results'] if isinstance(response.data, dict) else response.data
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]['name'], 'My Trip')

    def test_create_trip_with_stops(self):
        payload = {
            'name': 'Road Trip',
            'date': '2026-08-15',
            'stops': [
                {
                    'person': self.person.id,
                    'sequence_order': 1,
                    'location': {'type': 'Point', 'coordinates': [-87.6298, 41.8781]},
                },
                {
                    'person': self.person.id,
                    'sequence_order': 2,
                    'location': {'type': 'Point', 'coordinates': [-73.9857, 40.7484]},
                },
            ],
        }
        response = self.client.post('/api/trips/', payload, format='json')
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['name'], 'Road Trip')
        self.assertEqual(len(response.data['stops']), 2)
        self.assertEqual(Trip.objects.filter(user=self.user).count(), 1)

    def test_update_replaces_stops(self):
        trip = Trip.objects.create(name='Old', date='2026-07-01', user=self.user)
        TripStop.objects.create(
            trip=trip, person=self.person, sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        payload = {
            'name': 'Updated',
            'date': '2026-09-01',
            'stops': [
                {
                    'person': self.person.id,
                    'sequence_order': 1,
                    'location': {'type': 'Point', 'coordinates': [-73.9857, 40.7484]},
                },
                {
                    'person': self.person.id,
                    'sequence_order': 2,
                    'location': {'type': 'Point', 'coordinates': [-87.6298, 41.8781]},
                },
            ],
        }
        response = self.client.put(f'/api/trips/{trip.id}/', payload, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['name'], 'Updated')
        self.assertEqual(len(response.data['stops']), 2)
        self.assertEqual(TripStop.objects.filter(trip=trip).count(), 2)

    def test_cannot_access_other_users_trip(self):
        other_trip = Trip.objects.create(
            name='Secret Trip', date='2026-07-01', user=self.other_user
        )
        response = self.client.get(f'/api/trips/{other_trip.id}/')
        self.assertEqual(response.status_code, 404)

    def test_delete_trip(self):
        trip = Trip.objects.create(name='Doomed Trip', date='2026-07-01', user=self.user)
        response = self.client.delete(f'/api/trips/{trip.id}/')
        self.assertEqual(response.status_code, 204)
        self.assertFalse(Trip.objects.filter(id=trip.id).exists())
