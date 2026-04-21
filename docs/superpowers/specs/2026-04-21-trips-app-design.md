# Trips App — Backend Design Spec

**Date:** 2026-04-21
**ClickUp task:** 86b9gcuha
**Status:** Approved

---

## Overview

Add a `trips` Django app to `backend/apps/` that lets authenticated users create, read, update, and delete multi-stop travel plans. Trips are strictly user-scoped — a user can only see and modify their own trips.

---

## Models (`backend/apps/trips/models.py`)

### `Trip`

| Field  | Type                                                                 | Notes                        |
|--------|----------------------------------------------------------------------|------------------------------|
| `name` | `CharField(max_length=255)`                                          |                              |
| `date` | `DateField`                                                          |                              |
| `user` | `ForeignKey(settings.AUTH_USER_MODEL, on_delete=CASCADE, related_name='trips')` | Set server-side on create |

### `TripStop`

| Field            | Type                                                      | Notes                                         |
|------------------|-----------------------------------------------------------|-----------------------------------------------|
| `trip`           | `ForeignKey(Trip, on_delete=CASCADE, related_name='stops')` |                                             |
| `person`         | `ForeignKey('people.Person', on_delete=CASCADE)`          | Links stop to a map contact                   |
| `sequence_order` | `PositiveIntegerField()`                                  | Controls ordering within the trip             |
| `location`       | `PointField()`                                            | Meeting location (distinct from person's home)|

`TripStop.Meta.ordering = ['sequence_order']` — ORM always returns stops in order.

---

## Serializers (`backend/apps/trips/serializers.py`)

### `TripStopSerializer`

- Base class: `ModelSerializer`
- Fields: `id`, `person`, `sequence_order`, `location`
- `location` uses `rest_framework_gis.fields.GeometryField` for transparent GeoJSON ↔ PostGIS conversion

### `TripSerializer`

- Base class: `ModelSerializer`
- Fields: `id`, `name`, `date`, `stops`
- `stops = TripStopSerializer(many=True)` — nested, read and write
- `user` excluded from the serializer (set server-side via `perform_create`)
- Overrides `create` and `update` to handle nested stop writes:
  - On `update`: delete all existing stops for the trip, then recreate from the payload (correct for ordered sequences, avoids diffing complexity)

---

## Views (`backend/apps/trips/views.py`)

### `TripViewSet(viewsets.ModelViewSet)`

- **Queryset:** `Trip.objects.filter(user=request.user).prefetch_related('stops')`
- **Permissions:** `IsAuthenticated` on all actions
- **`perform_create`:** injects `user=request.user`
- **Serializer:** `TripSerializer`

---

## URLs & Registration

### `backend/apps/trips/urls.py`

`DefaultRouter` registers `TripViewSet` at `r''`.

Resulting routes:

| Method | URL              | Action    |
|--------|------------------|-----------|
| GET    | `/api/trips/`    | list      |
| POST   | `/api/trips/`    | create    |
| GET    | `/api/trips/{id}/` | retrieve |
| PUT    | `/api/trips/{id}/` | update   |
| PATCH  | `/api/trips/{id}/` | partial_update |
| DELETE | `/api/trips/{id}/` | destroy  |

### `backend/config/urls.py`

Add: `path('api/trips/', include('apps.trips.urls'))`

### `backend/config/settings.py`

Add `'apps.trips'` to `INSTALLED_APPS`.

### `backend/apps/trips/apps.py`

`TripsConfig` with `default_auto_field = 'django.db.models.BigAutoField'` and `name = 'apps.trips'`.

### `backend/apps/trips/admin.py`

Register `Trip` with a `TabularInline` for `TripStop` so stops are editable inside the trip admin page.

---

## Out of Scope

- Sharing trips with other users
- Per-stop notes or timestamps
- Frontend changes
