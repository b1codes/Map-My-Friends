from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.common.ownership import owner_key_for

from .repositories import DuplicateSequenceOrder, TripRepository
from .serializers import (
    TripLegSerializer,
    TripSerializer,
    TripStopSerializer,
    stop_context,
)
from .services import OSRMService, RoutingError, TransportLookupService


class TripViewSet(viewsets.ViewSet):
    permission_classes = [IsAuthenticated]

    @property
    def repository(self):
        return TripRepository()

    @staticmethod
    def _represent(request, trips, many=False):
        stops = [stop for trip in (trips if many else [trips]) for stop in trip.stops]
        return TripSerializer(
            trips, many=many, context=stop_context(request, stops)
        ).data

    def list(self, request):
        trips = self.repository.list_for_owner(owner_key_for(request))
        return Response(self._represent(request, trips, many=True))

    def retrieve(self, request, pk=None):
        trip = self.repository.get_for_owner(pk, owner_key_for(request))
        if trip is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(self._represent(request, trip))

    @staticmethod
    def _split_payload(validated):
        """Separate the nested children from the trip's own fields."""
        data = dict(validated)
        stops = data.pop("stops", None)
        legs = data.pop("legs", None)
        payload = {
            k: (v.isoformat() if hasattr(v, "isoformat") else v)
            for k, v in data.items()
        }
        return payload, stops, legs

    def create(self, request):
        serializer = TripSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payload, stops, _legs = self._split_payload(serializer.validated_data)

        owner_key = owner_key_for(request)
        trip = self.repository.create(owner_key, payload)
        if stops:
            self.repository.replace_stops(trip.id, owner_key, stops)
            trip = self.repository.get_for_owner(trip.id, owner_key)
        return Response(self._represent(request, trip), status=status.HTTP_201_CREATED)

    def update(self, request, pk=None):
        return self._write_update(request, pk, partial=False)

    def partial_update(self, request, pk=None):
        return self._write_update(request, pk, partial=True)

    def _write_update(self, request, pk, partial):
        serializer = TripSerializer(data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        payload, stops, legs = self._split_payload(serializer.validated_data)

        owner_key = owner_key_for(request)
        trip = self.repository.update(pk, owner_key, payload)
        if trip is None:
            return Response(status=status.HTTP_404_NOT_FOUND)

        # Matching the old serializer: a supplied `stops` array replaces the
        # trip's stops wholesale, and `legs` patches existing legs by id.
        if stops is not None:
            self.repository.replace_stops(pk, owner_key, stops)
        if legs:
            for leg in legs:
                leg_id = leg.get("id")
                if not leg_id:
                    continue
                leg_payload = {
                    k: (v.isoformat() if hasattr(v, "isoformat") else v)
                    for k, v in leg.items()
                    if k
                    not in ("id", "trip_id", "departure_stop_id", "arrival_stop_id")
                }
                if leg_payload:
                    self.repository.update_leg(pk, leg_id, owner_key, leg_payload)

        trip = self.repository.get_for_owner(pk, owner_key)
        return Response(self._represent(request, trip))

    def destroy(self, request, pk=None):
        if not self.repository.delete(pk, owner_key_for(request)):
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["get", "post"], url_path="stops")
    def stops(self, request, pk=None):
        owner_key = owner_key_for(request)
        if request.method == "GET":
            stops = self.repository.list_stops(pk, owner_key)
            return Response(
                TripStopSerializer(
                    stops, many=True, context=stop_context(request, stops)
                ).data
            )

        serializer = TripStopSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            stop = self.repository.add_stop(
                pk, owner_key, dict(serializer.validated_data)
            )
        except DuplicateSequenceOrder as exc:
            return Response(
                {"sequence_order": [str(exc)]}, status=status.HTTP_400_BAD_REQUEST
            )
        if stop is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(
            TripStopSerializer(stop, context=stop_context(request, [stop])).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=["post"])
    def calculate_route(self, request):
        coordinates = request.data.get("coordinates")

        if not coordinates or not isinstance(coordinates, list):
            return Response(
                {
                    "error": 'Missing or invalid "coordinates" in payload. Expected a list of [lon, lat].'
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Validate structure: list of lists with 2 numeric values
        for coord in coordinates:
            if not isinstance(coord, list) or len(coord) != 2:
                return Response(
                    {
                        "error": "Each coordinate must be a list of two numbers: [longitude, latitude]."
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            try:
                float(coord[0])
                float(coord[1])
            except (ValueError, TypeError):
                return Response(
                    {"error": "Coordinates must be numeric values."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        try:
            geometry = OSRMService.get_route(coordinates)
            return Response(geometry, status=status.HTTP_200_OK)
        except RoutingError as e:
            return Response({"error": str(e)}, status=e.status_code)


class TripLegViewSet(viewsets.ViewSet):
    permission_classes = [IsAuthenticated]

    @property
    def repository(self):
        return TripRepository()

    def list(self, request):
        owner_key = owner_key_for(request)
        legs = []
        for trip in self.repository.list_for_owner(owner_key):
            legs.extend(self.repository.list_legs(trip.id, owner_key))
        return Response(TripLegSerializer(legs, many=True).data)

    def _find_leg(self, leg_id, owner_key):
        for trip in self.repository.list_for_owner(owner_key):
            for leg in self.repository.list_legs(trip.id, owner_key):
                if leg.id == leg_id:
                    return leg
        return None

    def retrieve(self, request, pk=None):
        leg = self._find_leg(pk, owner_key_for(request))
        if leg is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(TripLegSerializer(leg).data)

    def partial_update(self, request, pk=None):
        owner_key = owner_key_for(request)
        leg = self._find_leg(pk, owner_key)
        if leg is None:
            return Response(status=status.HTTP_404_NOT_FOUND)

        serializer = TripLegSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        # `id` addresses the leg; the doc id is the id, so it is never written.
        payload = {
            k: (v.isoformat() if hasattr(v, "isoformat") else v)
            for k, v in serializer.validated_data.items()
            if k != "id"
        }
        # Firestore rejects an empty update, so a no-op PATCH returns the leg.
        if not payload:
            return Response(TripLegSerializer(leg).data)
        updated = self.repository.update_leg(leg.trip_id, pk, owner_key, payload)
        return Response(TripLegSerializer(updated).data)

    @action(detail=True, methods=["post"])
    def smart_lookup(self, request, pk=None):
        owner_key = owner_key_for(request)
        leg = self._find_leg(pk, owner_key)
        if leg is None:
            return Response(status=status.HTTP_404_NOT_FOUND)

        identifier = request.data.get("identifier", leg.booking_reference)
        if not identifier:
            return Response(
                {"error": "Missing identifier"}, status=status.HTTP_400_BAD_REQUEST
            )
        if not isinstance(identifier, str):
            return Response(
                {"error": "Identifier must be a string"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        data = {}
        if leg.transport_type == "FLIGHT":
            data = TransportLookupService.lookup_flight(identifier)
        elif leg.transport_type == "TRAIN":
            data = TransportLookupService.lookup_train(identifier)

        if data:
            ticket_data = dict(leg.ticket_data)
            ticket_data.update(data)
            payload = {"ticket_data": ticket_data}
            if "departure" in data and "time" in data["departure"]:
                payload["departure_time"] = data["departure"]["time"]
            if "arrival" in data and "time" in data["arrival"]:
                payload["arrival_time"] = data["arrival"]["time"]

            updated = self.repository.update_leg(leg.trip_id, pk, owner_key, payload)
            return Response(TripLegSerializer(updated).data)

        return Response(
            {"message": "No data found for this identifier"},
            status=status.HTTP_404_NOT_FOUND,
        )
