from django.db import transaction
from rest_framework import serializers
from rest_framework_gis.fields import GeometryField
from apps.people.models import Person
from apps.airports.models import Airport
from apps.stations.models import Station
from .models import Trip, TripStop, TripLeg


class TripStopSerializer(serializers.ModelSerializer):
    location = GeometryField()
    people = serializers.PrimaryKeyRelatedField(
        queryset=Person.objects.all(),
        many=True,
        required=False,
        default=[],
    )
    airport = serializers.PrimaryKeyRelatedField(
        queryset=Airport.objects.all(),
        allow_null=True,
        required=False,
        default=None,
    )
    station = serializers.PrimaryKeyRelatedField(
        queryset=Station.objects.all(),
        allow_null=True,
        required=False,
        default=None,
    )

    class Meta:
        model = TripStop
        fields = ('id', 'people', 'airport', 'station', 'sequence_order', 'location', 'snapshot_address', 'snapshot_metadata')
        read_only_fields = ('snapshot_address', 'snapshot_metadata')


class TripLegSerializer(serializers.ModelSerializer):
    class Meta:
        model = TripLeg
        fields = ('id', 'departure_stop', 'arrival_stop', 'departure_time', 'arrival_time', 'transport_type', 'booking_reference', 'ticket_data')


class TripSerializer(serializers.ModelSerializer):
    stops = TripStopSerializer(many=True)
    legs = TripLegSerializer(many=True, required=False)

    class Meta:
        model = Trip
        fields = ('id', 'name', 'date', 'start_date', 'end_date', 'status', 'stops', 'legs')

    def create(self, validated_data):
        with transaction.atomic():
            stops_data = validated_data.pop('stops')
            legs_data = validated_data.pop('legs', [])
            trip = Trip.objects.create(**validated_data)
            
            for stop_data in stops_data:
                people = stop_data.pop('people', [])
                stop = TripStop.objects.create(trip=trip, **stop_data)
                stop.people.set(people)
                
            trip.generate_legs()
        return trip

    def update(self, instance, validated_data):
        with transaction.atomic():
            stops_data = validated_data.pop('stops', None)
            legs_data = validated_data.pop('legs', None)
            
            for attr, value in validated_data.items():
                setattr(instance, attr, value)
            instance.save()
            
            if stops_data is not None:
                instance.stops.all().delete()
                for stop_data in stops_data:
                    people = stop_data.pop('people', [])
                    stop = TripStop.objects.create(trip=instance, **stop_data)
                    stop.people.set(people)
                
                instance.generate_legs()
                
            if legs_data:
                self._update_legs(instance, legs_data)
                    
        return instance

    def _update_legs(self, trip, legs_data):
        for leg_data in legs_data:
            leg_id = leg_data.get('id')
            if leg_id:
                try:
                    leg = TripLeg.objects.get(id=leg_id, trip=trip)
                    for attr, value in leg_data.items():
                        if attr != 'id':
                            setattr(leg, attr, value)
                    leg.save()
                except TripLeg.DoesNotExist:
                    pass
