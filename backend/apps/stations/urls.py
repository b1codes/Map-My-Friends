from django.urls import path
from .views import NearestStationsView

urlpatterns = [
    path('nearest/', NearestStationsView.as_view(), name='nearest-stations'),
]
