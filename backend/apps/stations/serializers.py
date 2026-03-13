from rest_framework import serializers
from rest_framework_gis.serializers import GeoFeatureModelSerializer
from .models import Station


class StationSerializer(GeoFeatureModelSerializer):
    distance_km = serializers.FloatField(read_only=True, required=False)

    class Meta:
        model = Station
        geo_field = "location"
        fields = (
            'id',
            'name',
            'osm_id',
            'station_type',
            'uic_ref',
            'city',
            'country',
            'location',
            'distance_km',
        )
