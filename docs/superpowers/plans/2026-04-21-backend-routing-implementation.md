# Backend Routing Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a backend routing service that calculates routes via the OSRM public API and expose it through a new action on the `TripViewSet`.

**Architecture:** A new `OSRMService` class in `services.py` will handle external HTTP requests. A `@action` decorator on `TripViewSet` will validate the payload and return the route geometry.

**Tech Stack:** Python, Django REST Framework, requests.

---

## File Map

**Create:**
- `backend/apps/trips/services.py`

**Modify:**
- `backend/apps/trips/views.py`

---

## Task 1: OSRM Service

- [ ] **Step 1: Create `backend/apps/trips/services.py`**

```python
import requests
from rest_framework.exceptions import APIException

class RoutingError(APIException):
    status_code = 400
    default_detail = 'Routing calculation failed.'
    default_code = 'routing_error'

class OSRMService:
    BASE_URL = 'https://router.project-osrm.org/route/v1/driving'

    @classmethod
    def get_route(cls, coordinates: list[list[float]]) -> dict:
        if not coordinates or len(coordinates) < 2:
            raise RoutingError('At least two coordinates are required.')
            
        if len(coordinates) > 25:
             raise RoutingError('Maximum of 25 coordinates allowed.')

        coords_str = ';'.join([f"{lon},{lat}" for lon, lat in coordinates])
        url = f"{cls.BASE_URL}/{coords_str}?overview=full&geometries=geojson"

        try:
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            if data.get('code') != 'Ok' or not data.get('routes'):
                raise RoutingError(f"OSRM returned error: {data.get('message', 'No route found')}")

            return data['routes'][0]['geometry']
        except requests.RequestException as e:
            raise RoutingError(f"External routing service error: {str(e)}")
```

- [ ] **Step 2: Commit**

```bash
git add backend/apps/trips/services.py
git commit -m "feat(trips): add OSRMService for route calculation"
```

---

## Task 2: TripViewSet Action

- [ ] **Step 1: Modify `backend/apps/trips/views.py`**

Add the `calculate_route` action to `TripViewSet`.

```python
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework import status
from .services import OSRMService, RoutingError

# Inside TripViewSet class:

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
```

- [ ] **Step 2: Run Tests & Checks**

We must ensure there are no syntax errors.
```bash
make shell -c "from apps.trips.views import TripViewSet; print('Syntax OK')"
```

- [ ] **Step 3: Commit**

```bash
git add backend/apps/trips/views.py
git commit -m "feat(trips): add calculate_route action to TripViewSet"
```
