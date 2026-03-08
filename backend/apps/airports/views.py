from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from django.contrib.gis.geos import Point
from django.contrib.gis.db.models.functions import Distance

from .models import Airport
from .serializers import AirportSerializer


class NearestAirportsView(APIView):
    """
    Return the N nearest airports to a given latitude/longitude.

    Query params:
        lat (float): Latitude
        lon (float): Longitude
        count (int): Number of airports to return (default 3, max 10)
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            lat = float(request.query_params.get('lat'))
            lon = float(request.query_params.get('lon'))
        except (TypeError, ValueError):
            return Response(
                {'error': 'lat and lon query parameters are required and must be numbers.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            count = int(request.query_params.get('count', 3))
            count = min(max(count, 1), 10)  # Clamp between 1 and 10
        except (TypeError, ValueError):
            count = 3

        user_location = Point(lon, lat, srid=4326)

        airports = (
            Airport.objects
            .annotate(distance=Distance('location', user_location))
            .order_by('distance')[:count]
        )

        # Add distance_km as a plain float for the serializer
        airport_list = []
        for airport in airports:
            airport.distance_km = round(airport.distance.km, 1)
            airport_list.append(airport)

        serializer = AirportSerializer(airport_list, many=True)
        return Response(serializer.data)
