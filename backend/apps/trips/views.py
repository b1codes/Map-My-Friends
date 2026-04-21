from rest_framework import viewsets, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import Trip
from .serializers import TripSerializer
from .services import OSRMService, RoutingError


class TripViewSet(viewsets.ModelViewSet):
    serializer_class = TripSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Trip.objects.filter(user=self.request.user).prefetch_related('stops')

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @action(detail=False, methods=['post'])
    def calculate_route(self, request):
        coordinates = request.data.get('coordinates')

        if not coordinates or not isinstance(coordinates, list):
            return Response(
                {'error': 'Missing or invalid "coordinates" in payload. Expected a list of [lon, lat].'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Validate structure: list of lists with 2 numeric values
        for coord in coordinates:
            if not isinstance(coord, list) or len(coord) != 2:
                return Response(
                    {'error': 'Each coordinate must be a list of two numbers: [longitude, latitude].'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            try:
                float(coord[0])
                float(coord[1])
            except (ValueError, TypeError):
                return Response(
                    {'error': 'Coordinates must be numeric values.'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        try:
            geometry = OSRMService.get_route(coordinates)
            return Response(geometry, status=status.HTTP_200_OK)
        except RoutingError as e:
            return Response({'error': str(e)}, status=e.status_code)
