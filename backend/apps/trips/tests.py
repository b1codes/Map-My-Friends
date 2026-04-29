import datetime
from django.test import TestCase
from django.contrib.auth.models import User
from django.contrib.gis.geos import Point
from apps.people.models import Person
from .models import Trip, TripStop, TripLeg
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
        stop2 = TripStop.objects.create(
            trip=trip,
            sequence_order=2,
            location=Point(-73.9857, 40.7484, srid=4326),
        )
        stop2.people.set([self.person])
        stop1 = TripStop.objects.create(
            trip=trip,
            sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        stop1.people.set([self.person])
        stops = list(trip.stops.all())
        self.assertEqual(stops[0].sequence_order, 1)
        self.assertEqual(stops[1].sequence_order, 2)

    def test_tripstop_cascade_delete(self):
        trip = Trip.objects.create(
            name='Test Trip',
            date=datetime.date(2026, 7, 4),
            user=self.user,
        )
        stop = TripStop.objects.create(
            trip=trip,
            sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        stop.people.set([self.person])
        trip_id = trip.id
        trip.delete()
        self.assertFalse(TripStop.objects.filter(trip_id=trip_id).exists())

    def test_trip_snapshotting_on_status_change(self):
        trip = Trip.objects.create(
            name='Snapshot Trip',
            date=datetime.date(2026, 7, 4),
            user=self.user,
            status=Trip.Status.DRAFT,
        )
        stop = TripStop.objects.create(
            trip=trip,
            sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        stop.people.set([self.person])
        
        # Initially snapshots should be empty
        self.assertEqual(stop.snapshot_address, '')
        self.assertEqual(stop.snapshot_metadata, {})

        # Transition to BOOKED
        trip.status = Trip.Status.BOOKED
        trip.save()

        stop.refresh_from_db()
        self.assertIn('Jane Doe', stop.snapshot_address)
        self.assertIn('Chicago', stop.snapshot_address)
        self.assertEqual(stop.snapshot_metadata['people'][0]['name'], 'Jane Doe')

    def test_trip_snapshot_remains_frozen(self):
        trip = Trip.objects.create(
            name='Frozen Trip',
            date=datetime.date(2026, 7, 4),
            user=self.user,
            status=Trip.Status.DRAFT,
        )
        stop = TripStop.objects.create(
            trip=trip,
            sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        stop.people.set([self.person])

        # Transition to BOOKED to trigger snapshot
        trip.status = Trip.Status.BOOKED
        trip.save()
        
        stop.refresh_from_db()
        original_address = stop.snapshot_address
        original_name = stop.snapshot_metadata['people'][0]['name']

        # Modify Person
        self.person.first_name = 'Janet'
        self.person.city = 'New York'
        self.person.save()

        # Re-verify snapshot hasn't changed
        stop.refresh_from_db()
        self.assertEqual(stop.snapshot_address, original_address)
        self.assertEqual(stop.snapshot_metadata['people'][0]['name'], original_name)
        self.assertIn('Jane Doe', stop.snapshot_address)
        self.assertIn('Chicago', stop.snapshot_address)


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
        s2 = TripStop.objects.create(
            trip=trip, sequence_order=2,
            location=Point(-73.9857, 40.7484, srid=4326),
        )
        s2.people.set([self.person])
        s1 = TripStop.objects.create(
            trip=trip, sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        s1.people.set([self.person])
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
                    'people': [self.person.id],
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
        s = TripStop.objects.create(
            trip=trip, sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        s.people.set([self.person])
        data = {
            'name': 'Updated Trip',
            'date': '2026-09-15',
            'stops': [
                {
                    'people': [self.person.id],
                    'sequence_order': 1,
                    'location': {'type': 'Point', 'coordinates': [-73.9857, 40.7484]},
                },
                {
                    'people': [self.person.id],
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
        s1 = TripStop.objects.create(
            trip=trip, sequence_order=1,
            location=Point(-87.6298, 41.8781, srid=4326),
        )
        s1.people.set([self.person])
        s2 = TripStop.objects.create(
            trip=trip, sequence_order=2,
            location=Point(-73.9857, 40.7484, srid=4326),
        )
        s2.people.set([self.person])
        # Update with stops where sequence_order 2 overlaps with old stop 2 but is a different stop
        data = {
            'name': 'Overlap Trip',
            'date': '2026-08-01',
            'stops': [
                {
                    'people': [self.person.id],
                    'sequence_order': 2,
                    'location': {'type': 'Point', 'coordinates': [-87.6298, 41.8781]},
                },
                {
                    'people': [self.person.id],
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


class TripLegTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(username='leguser', password='pw')
        self.client.force_authenticate(user=self.user)
        self.person = Person.objects.create(
            tag='FRIEND',
            first_name='Charlie',
            last_name='Brown',
            city='Chicago',
            state='IL',
            country='US',
            location=Point(-87.6298, 41.8781, srid=4326),
        )

    def test_legs_auto_created_on_trip_create(self):
        payload = {
            'name': 'Leggy Trip',
            'date': '2026-08-15',
            'stops': [
                {
                    'people': [self.person.id],
                    'sequence_order': 1,
                    'location': {'type': 'Point', 'coordinates': [-87.6298, 41.8781]},
                },
                {
                    'people': [self.person.id],
                    'sequence_order': 2,
                    'location': {'type': 'Point', 'coordinates': [-73.9857, 40.7484]},
                },
            ],
        }
        response = self.client.post('/api/trips/', payload, format='json')
        self.assertEqual(response.status_code, 201)
        trip_id = response.data['id']
        trip = Trip.objects.get(id=trip_id)
        self.assertEqual(trip.legs.count(), 1)
        leg = trip.legs.first()
        self.assertEqual(leg.departure_stop.sequence_order, 1)
        self.assertEqual(leg.arrival_stop.sequence_order, 2)

    def test_update_leg_details(self):
        trip = Trip.objects.create(name='Leg Trip', date='2026-07-01', user=self.user)
        s1 = TripStop.objects.create(trip=trip, sequence_order=1, location=Point(0, 0))
        s2 = TripStop.objects.create(trip=trip, sequence_order=2, location=Point(1, 1))
        leg = TripLeg.objects.create(trip=trip, departure_stop=s1, arrival_stop=s2)
        
        payload = {
            'transport_type': 'FLIGHT',
            'booking_reference': 'ABC123',
            'ticket_data': {'seat': '12A'}
        }
        response = self.client.patch(f'/api/trips/legs/{leg.id}/', payload, format='json')
        self.assertEqual(response.status_code, 200)
        leg.refresh_from_db()
        self.assertEqual(leg.transport_type, 'FLIGHT')
        self.assertEqual(leg.booking_reference, 'ABC123')
        self.assertEqual(leg.ticket_data['seat'], '12A')

    def test_legs_regenerated_on_stop_reorder(self):
        trip = Trip.objects.create(name='Reorder Trip', date='2026-07-01', user=self.user)
        s1 = TripStop.objects.create(trip=trip, sequence_order=1, location=Point(0, 0))
        s2 = TripStop.objects.create(trip=trip, sequence_order=2, location=Point(1, 1))
        
        # Initially 1 leg
        self.assertEqual(TripLeg.objects.filter(trip=trip).count(), 1)
        
        # Update stops (reorder and add one)
        payload = {
            'name': 'Reorder Trip',
            'date': '2026-07-01',
            'stops': [
                {
                    'sequence_order': 1,
                    'location': {'type': 'Point', 'coordinates': [0, 0]},
                },
                {
                    'sequence_order': 2,
                    'location': {'type': 'Point', 'coordinates': [2, 2]},
                },
                {
                    'sequence_order': 3,
                    'location': {'type': 'Point', 'coordinates': [1, 1]},
                },
            ],
        }
        response = self.client.put(f'/api/trips/{trip.id}/', payload, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(TripLeg.objects.filter(trip=trip).count(), 2)
