from django.contrib import admin
from .models import Airport


@admin.register(Airport)
class AirportAdmin(admin.ModelAdmin):
    list_display = ('name', 'iata_code', 'icao_code', 'airport_type', 'city', 'country')
    list_filter = ('airport_type', 'continent', 'country')
    search_fields = ('name', 'iata_code', 'icao_code', 'city')
    ordering = ('name',)
