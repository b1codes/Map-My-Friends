from django.contrib.gis import admin
from .models import Trip, TripStop


class TripStopInline(admin.TabularInline):
    model = TripStop
    extra = 1
    fields = ('person', 'sequence_order', 'location')
    ordering = ('sequence_order',)


@admin.register(Trip)
class TripAdmin(admin.GISModelAdmin):
    list_display = ('name', 'date', 'user')
    list_filter = ('user',)
    inlines = [TripStopInline]
