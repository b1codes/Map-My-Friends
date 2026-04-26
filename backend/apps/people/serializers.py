from rest_framework import serializers
from django.contrib.gis.geos import Point
from rest_framework_gis.serializers import GeoFeatureModelSerializer
from .models import Person
from apps.airports.models import Airport
from apps.stations.models import Station
from apps.airports.serializers import AirportSerializer
from apps.stations.serializers import StationSerializer


class PersonSerializer(GeoFeatureModelSerializer):
    preferred_airport = serializers.PrimaryKeyRelatedField(
        queryset=Airport.objects.all(), allow_null=True, required=False
    )
    preferred_station = serializers.PrimaryKeyRelatedField(
        queryset=Station.objects.all(), allow_null=True, required=False
    )
    preferred_airport_detail = AirportSerializer(source='preferred_airport', read_only=True)
    preferred_station_detail = StationSerializer(source='preferred_station', read_only=True)

    class Meta:
        model = Person
        geo_field = "location"
        fields = (
            'id',
            'first_name',
            'last_name',
            'tag',
            'city',
            'state',
            'country',
            'street',
            'birthday',
            'phone_number',
            'profile_image',
            'location',
            'timezone',
            'pin_color',
            'pin_style',
            'pin_icon_type',
            'pin_emoji',
            'preferred_airport',
            'preferred_station',
            'preferred_airport_detail',
            'preferred_station_detail',
        )
        read_only_fields = ('location', 'timezone')
