from rest_framework import viewsets
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
