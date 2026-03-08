from django.urls import path
from .views import NearestAirportsView

urlpatterns = [
    path('nearest/', NearestAirportsView.as_view(), name='nearest_airports'),
]
