from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.geo import parse_lat_lon

from . import reference
from .serializers import StationSerializer

VALID_STATION_TYPES = {
    "major_station",
    "regional_station",
    "commuter_rail_station",
    "subway_station",
}


class NearestStationsView(APIView):
    """Return the N nearest train stations to a given latitude/longitude.

    Query params:
        lat (float): Latitude
        lon (float): Longitude
        count (int): Number of stations to return (default 3, max 10)
        station_type (str): Optional filter by station type
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
            count = min(max(count, 1), 10)
        except (TypeError, ValueError):
            count = 3

        station_type = request.query_params.get("station_type")
        if station_type not in VALID_STATION_TYPES:
            station_type = None

        stations = reference.get_nearby(
            lat, lon, count=count, station_type=station_type
        )
        return Response(StationSerializer(stations, many=True).data)
