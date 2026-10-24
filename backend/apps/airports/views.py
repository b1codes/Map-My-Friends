from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.geo import parse_lat_lon

from . import reference
from .serializers import AirportSerializer


class NearestAirportsView(APIView):
    """Return the N nearest airports to a given latitude/longitude.

    Query params:
        lat (float): Latitude
        lon (float): Longitude
        count (int): Number of airports to return (default 3, max 10)
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            lat, lon = parse_lat_lon(
                request.query_params.get("lat"), request.query_params.get("lon")
            )
        except ValueError as exc:
            return Response({"error": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        try:
            count = int(request.query_params.get("count", 3))
            count = min(max(count, 1), 10)  # Clamp between 1 and 10
        except (TypeError, ValueError):
            count = 3

        airports = reference.get_nearby(lat, lon, count=count)
        return Response(AirportSerializer(airports, many=True).data)
