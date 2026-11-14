from rest_framework import serializers

from apps.airports import reference as airport_reference
from apps.airports.serializers import AirportSerializer
from apps.common.fields import PinColorField
from apps.common.serializers import GeoFeatureSerializer
from apps.stations import reference as station_reference
from apps.stations.serializers import StationSerializer

TAG_CHOICES = ["FRIEND", "FAMILY"]
PIN_STYLE_CHOICES = ["teardrop", "circle", "square", "triangle", "diamond"]
PIN_ICON_TYPE_CHOICES = ["none", "emoji", "initials", "picture"]
CHANNEL_CHOICES = ["CALL", "VIDEO", "MESSAGE"]


class ContactLogSerializer(serializers.Serializer):
    id = serializers.CharField(read_only=True)
    person = serializers.CharField(source="person_id")
    channel = serializers.ChoiceField(choices=CHANNEL_CHOICES)
    contacted_at = serializers.DateTimeField()
    note = serializers.CharField(
        max_length=280, required=False, allow_null=True, allow_blank=True
    )
    created_at = serializers.DateTimeField(read_only=True)


class PersonSerializer(GeoFeatureSerializer):
    id = serializers.CharField(read_only=True)
    owner = serializers.CharField(source="owner_key", read_only=True)
    tag = serializers.ChoiceField(choices=TAG_CHOICES)
    first_name = serializers.CharField(max_length=100, required=False, allow_blank=True)
    last_name = serializers.CharField(max_length=100, required=False, allow_blank=True)
    city = serializers.CharField(max_length=100, required=False, allow_blank=True)
    state = serializers.CharField(max_length=100, required=False, allow_blank=True)
    country = serializers.CharField(max_length=100, required=False, allow_blank=True)
    street = serializers.CharField(
        max_length=255, required=False, allow_null=True, allow_blank=True
    )
    # Dart's DateTime.toIso8601String() yields "1990-01-02T00:00:00.000",
    # which DRF's default DateField input_formats reject (400). Accept the
    # datetime forms the client actually sends alongside plain dates.
    birthday = serializers.DateField(
        required=False,
        allow_null=True,
        input_formats=["iso-8601", "%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S"],
    )
    phone_number = serializers.CharField(
        required=False, allow_null=True, allow_blank=True
    )
    profile_image = serializers.SerializerMethodField()
    lat = serializers.FloatField(read_only=True)
    lng = serializers.FloatField(read_only=True)
    timezone = serializers.CharField(read_only=True, allow_null=True)
    pin_color = PinColorField(required=False)
    pin_style = serializers.ChoiceField(choices=PIN_STYLE_CHOICES, required=False)
    pin_icon_type = serializers.ChoiceField(
        choices=PIN_ICON_TYPE_CHOICES, required=False
    )
    pin_emoji = serializers.CharField(
        max_length=10, required=False, allow_null=True, allow_blank=True
    )
    contact_cadence_days = serializers.IntegerField(
        required=False, allow_null=True, min_value=0
    )
    preferred_airport = serializers.IntegerField(required=False, allow_null=True)
    preferred_station = serializers.IntegerField(required=False, allow_null=True)
    preferred_airport_detail = serializers.SerializerMethodField()
    preferred_station_detail = serializers.SerializerMethodField()
    last_contacted_at = serializers.CharField(read_only=True, allow_null=True)
    last_contact_channel = serializers.CharField(read_only=True, allow_null=True)

    def get_profile_image(self, obj):
        from apps.common.storage import upload_url

        return upload_url(
            getattr(obj, "profile_image", None), self.context.get("request")
        )

    def get_preferred_airport_detail(self, obj):
        if not obj.preferred_airport:
            return None
        airport = airport_reference.get_by_id(obj.preferred_airport)
        return AirportSerializer(airport).data if airport else None

    def get_preferred_station_detail(self, obj):
        if not obj.preferred_station:
            return None
        station = station_reference.get_by_id(obj.preferred_station)
        return StationSerializer(station).data if station else None

    def validate_preferred_airport(self, value):
        if value is not None and airport_reference.get_by_id(value) is None:
            raise serializers.ValidationError("Unknown airport id.")
        return value

    def validate_preferred_station(self, value):
        if value is not None and station_reference.get_by_id(value) is None:
            raise serializers.ValidationError("Unknown station id.")
        return value

    def to_representation(self, instance):
        ret = super().to_representation(instance)
        request = self.context.get("request")
        is_authenticated = bool(
            request and request.user and request.user.is_authenticated
        )
        if not is_authenticated:
            ret["properties"].pop("last_contacted_at", None)
            ret["properties"].pop("last_contact_channel", None)
        return ret
