from django.db import transaction
from rest_framework import serializers
from rest_framework_gis.fields import GeometryField
from apps.people.models import Person
from .models import Trip, TripStop


class TripStopSerializer(serializers.ModelSerializer):
    location = GeometryField()
    person = serializers.PrimaryKeyRelatedField(
        queryset=Person.objects.all(),
        allow_null=True,
        required=False,
        default=None,
    )

    class Meta:
        model = TripStop
        fields = ('id', 'person', 'sequence_order', 'location')


class TripSerializer(serializers.ModelSerializer):
    stops = TripStopSerializer(many=True)

    class Meta:
        model = Trip
        fields = ('id', 'name', 'date', 'stops')

    def create(self, validated_data):
        with transaction.atomic():
            stops_data = validated_data.pop('stops')
            trip = Trip.objects.create(**validated_data)
            for stop_data in stops_data:
                TripStop.objects.create(trip=trip, **stop_data)
        return trip

    def update(self, instance, validated_data):
        with transaction.atomic():
            stops_data = validated_data.pop('stops', None)
            instance.name = validated_data.get('name', instance.name)
            instance.date = validated_data.get('date', instance.date)
            instance.save()
            if stops_data is not None:
                instance.stops.all().delete()
                for stop_data in stops_data:
                    TripStop.objects.create(trip=instance, **stop_data)
        return instance
