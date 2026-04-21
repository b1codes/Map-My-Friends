from rest_framework import viewsets, decorators, response, status
from rest_framework.permissions import IsAuthenticated

from .models import Trip
from .serializers import TripSerializer


class TripViewSet(viewsets.ModelViewSet):
    serializer_class = TripSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Trip.objects.filter(user=self.request.user).prefetch_related('stops')

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @decorators.action(detail=True, methods=['post'])
    def calculate_route(self, request, pk=None):
        trip = self.get_object()
        # Mock calculation logic for now as requested by task
        # In a real scenario, this would interface with OSRM
        return response.Response(
            {'status': 'route_calculated', 'trip_id': trip.id},
            status=status.HTTP_200_OK
        )
