from rest_framework import viewsets
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.throttling import UserRateThrottle

from .models import Person
from .serializers import PersonSerializer


class PersonViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing Person objects.
    List and retrieve are public, create/update/delete require authentication.
    """
    queryset = Person.objects.all()
    serializer_class = PersonSerializer
    
    def get_permissions(self):
        if self.action in ['list', 'retrieve']:
            permission_classes = [AllowAny]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]

    def get_throttles(self):
        if self.action == 'create':
            # Stricter throttling for creating people due to geocoding costs
            return [UserRateThrottle()]
        return super().get_throttles()

