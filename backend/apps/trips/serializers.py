from rest_framework import serializers

from apps.airports import reference as airport_reference
from apps.airports.serializers import AirportSerializer
from apps.common.ownership import owner_key_for
from apps.people.repositories import PersonRepository
from apps.stations import reference as station_reference
from apps.stations.serializers import StationSerializer

STATUS_CHOICES = ["DRAFT", "BOOKED", "CANCELLED"]
TRANSPORT_CHOICES = ["FLIGHT", "TRAIN", "BUS", "CAR"]


class PointField(serializers.Field):
    """GeoJSON Point <-> flat lat/lng, replacing rest_framework_gis's GeometryField.

    Firestore stores plain `lat`/`lng` numbers, but the API contract is a
    GeoJSON Point and the Flutter client depends on it in both directions:
    TripStop.toJson sends {'type': 'Point', 'coordinates': [lng, lat]} and
    TripStop.fromJson reads json['location']['coordinates'] with no fallback.
    Coordinates are [longitude, latitude] per the GeoJSON spec.
    """

    def get_attribute(self, instance):
        # The field spans two source attributes, so take the record itself.
        return instance

    def to_representation(self, instance):
        lat = getattr(instance, "lat", None)
        lng = getattr(instance, "lng", None)
        if lat is None or lng is None:
            return None
        return {"type": "Point", "coordinates": [lng, lat]}

    def to_internal_value(self, data):
        if not isinstance(data, dict):
            raise serializers.ValidationError(
                "Expected a GeoJSON Point object, e.g. "
                '{"type": "Point", "coordinates": [lng, lat]}.'
            )
        coordinates = data.get("coordinates")
        if not isinstance(coordinates, (list, tuple)) or len(coordinates) != 2:
            raise serializers.ValidationError(
                "coordinates must be a two-element [longitude, latitude] list."
            )
        try:
            lng, lat = float(coordinates[0]), float(coordinates[1])
        except (TypeError, ValueError):
            raise serializers.ValidationError("coordinates must be numbers.")
        if not -90 <= lat <= 90 or not -180 <= lng <= 180:
            raise serializers.ValidationError(
                "coordinates out of range; expected [longitude, latitude]."
            )
        return {"lat": lat, "lng": lng}


class StopPersonSerializer(serializers.Serializer):
    """A person on a trip stop, flat rather than GeoJSON.

    TripStop.fromJson parses people_detail with Person.fromJson, which reads
    `latitude`/`longitude` keys instead of a geometry.
    """

    id = serializers.CharField(read_only=True)
    tag = serializers.CharField(read_only=True)
    first_name = serializers.CharField(read_only=True)
    last_name = serializers.CharField(read_only=True)
    city = serializers.CharField(read_only=True)
    state = serializers.CharField(read_only=True)
    country = serializers.CharField(read_only=True)
    street = serializers.CharField(read_only=True, allow_null=True)
    birthday = serializers.CharField(read_only=True, allow_null=True)
    phone_number = serializers.CharField(read_only=True, allow_null=True)
    latitude = serializers.FloatField(source="lat", read_only=True, allow_null=True)
    longitude = serializers.FloatField(source="lng", read_only=True, allow_null=True)
    profile_image = serializers.SerializerMethodField()
    timezone = serializers.CharField(read_only=True, allow_null=True)
    pin_color = serializers.CharField(read_only=True)
    pin_style = serializers.CharField(read_only=True)
    pin_icon_type = serializers.CharField(read_only=True)
    pin_emoji = serializers.CharField(read_only=True, allow_null=True)

    def get_profile_image(self, obj):
        from apps.common.storage import upload_url

        return upload_url(obj.profile_image, self.context.get("request"))


class TripStopSerializer(serializers.Serializer):
    id = serializers.CharField(read_only=True)
    trip = serializers.CharField(source="trip_id", read_only=True)
    sequence_order = serializers.IntegerField(min_value=0)
    location = PointField()
    people = serializers.ListField(
        source="person_ids", child=serializers.CharField(), required=False
    )
    airport = serializers.IntegerField(
        source="airport_id", required=False, allow_null=True
    )
    station = serializers.IntegerField(
        source="station_id", required=False, allow_null=True
    )
    snapshot_address = serializers.CharField(read_only=True, allow_blank=True)
    snapshot_metadata = serializers.DictField(read_only=True)
    # What the planner draws and routes with after a reload: TripStop.fromJson
    # builds its people and hub from these, not from the bare ids above.
    people_detail = serializers.SerializerMethodField()
    airport_detail = serializers.SerializerMethodField()
    station_detail = serializers.SerializerMethodField()

    def get_people_detail(self, obj):
        # The views prefetch the owner's people into the context (see
        # stop_context), so ids that are not the owner's never resolve.
        people = self.context.get("people", {})
        return [
            StopPersonSerializer(people[person_id], context=self.context).data
            for person_id in obj.person_ids
            if person_id in people
        ]

    def get_airport_detail(self, obj):
        if not obj.airport_id:
            return None
        airport = airport_reference.get_by_id(obj.airport_id)
        return AirportSerializer(airport).data if airport else None

    def get_station_detail(self, obj):
        if not obj.station_id:
            return None
        station = station_reference.get_by_id(obj.station_id)
        return StationSerializer(station).data if station else None

    def to_internal_value(self, data):
        ret = super().to_internal_value(data)
        # DRF propagates root.partial into nested serializers, so on PATCH the
        # required=True on `location` is skipped. A stop persisted without
        # coordinates comes back as location: null, and TripStop.fromJson
        # dereferences it unguarded — one bad stop breaks the whole Trips tab.
        location = ret.pop("location", None)
        if not location:
            raise serializers.ValidationError({"location": ["This field is required."]})
        ret.update(location)
        return ret


class TripLegSerializer(serializers.Serializer):
    # Writable so update payloads can address a leg by id, but stripped before
    # the write so it never lands in the document (the doc id is the id).
    id = serializers.CharField(required=False, allow_null=True)
    trip = serializers.CharField(source="trip_id", read_only=True)
    departure_stop = serializers.CharField(source="departure_stop_id", read_only=True)
    arrival_stop = serializers.CharField(source="arrival_stop_id", read_only=True)
    departure_time = serializers.DateTimeField(required=False, allow_null=True)
    arrival_time = serializers.DateTimeField(required=False, allow_null=True)
    transport_type = serializers.ChoiceField(choices=TRANSPORT_CHOICES, required=False)
    booking_reference = serializers.CharField(
        max_length=100, required=False, allow_blank=True
    )
    ticket_data = serializers.DictField(required=False)


def stop_context(request, stops) -> dict:
    """Serializer context for stops: the request, plus the owner's people the
    stops name, read in one batch rather than once per stop."""
    person_ids = [person_id for stop in stops for person_id in stop.person_ids]
    people = PersonRepository().get_many_for_owner(person_ids, owner_key_for(request))
    return {"request": request, "people": people}


class TripSerializer(serializers.Serializer):
    """Trips carry their stops and legs inline.

    The pre-migration ModelSerializer nested both, created stops on POST and
    replaced them on PUT/PATCH. Flutter's Trip.fromJson reads json['stops']
    with no null guard, so a flat trip payload breaks the Trips tab outright.
    """

    id = serializers.CharField(read_only=True)
    name = serializers.CharField(max_length=255)
    date = serializers.DateField()
    start_date = serializers.DateField(required=False, allow_null=True)
    end_date = serializers.DateField(required=False, allow_null=True)
    status = serializers.ChoiceField(choices=STATUS_CHOICES, required=False)
    user = serializers.CharField(source="owner_key", read_only=True)
    stops = TripStopSerializer(many=True, required=False)
    legs = TripLegSerializer(many=True, required=False)
