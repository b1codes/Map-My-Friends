from rest_framework import serializers
from rest_framework_gis.serializers import GeoFeatureModelSerializer
from .models import Airport


class AirportSerializer(GeoFeatureModelSerializer):
    distance_km = serializers.FloatField(read_only=True, required=False)

    class Meta:
        model = Airport
        geo_field = "location"
        fields = (
            'id',
            'name',
            'iata_code',
            'icao_code',
            'airport_type',
            'city',
            'country',
            'continent',
            'location',
            'distance_km',
        )
