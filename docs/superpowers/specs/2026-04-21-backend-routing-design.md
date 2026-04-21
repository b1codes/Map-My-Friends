# Backend Trips App — Routing Integration Design Spec

**Date:** 2026-04-21
**ClickUp task:** 86b9gcuh9
**Status:** Approved

---

## Overview

Implement an API service to calculate routes between multiple stops using the public OSRM API. This feature will expose an endpoint that accepts a list of coordinates and returns the full route geometry as a GeoJSON LineString.

---

## Routing Service (`backend/apps/trips/services.py`)

Create a dedicated `OSRMService` to handle communication with the external OSRM API.

### `OSRMService`

-   **Responsibility:** Fetch routing data from OSRM.
-   **Method:** `get_route(coordinates: List[List[float]]) -> dict`
-   **URL:** `https://router.project-osrm.org/route/v1/driving/{coords}?overview=full&geometries=geojson`
    -   `{coords}` is a semicolon-separated string of `lon,lat` pairs.
-   **Return Value:** A dictionary representing a GeoJSON `LineString` feature (e.g., `{"type": "LineString", "coordinates": [...]}`).
-   **Error Handling:**
    -   Raise custom `RoutingError` if the OSRM API returns a non-200 status code, times out, or if the route cannot be found (e.g., locations disconnected by road).

---

## Endpoint (`backend/apps/trips/views.py`)

Add a custom action to the `TripViewSet` to handle route calculation requests.

### `calculate_route` Action

-   **Decorator:** `@action(detail=False, methods=['post'])`
-   **URL:** `/api/trips/calculate_route/`
-   **Permissions:** `IsAuthenticated`
-   **Input:** Expects a JSON body containing a list of `[longitude, latitude]` coordinate pairs.
    ```json
    {
      "coordinates": [
        [-122.4194, 37.7749],
        [-122.4312, 37.7652]
      ]
    }
    ```
-   **Output:** Returns a GeoJSON `LineString` representing the route.
    ```json
    {
      "type": "LineString",
      "coordinates": [
        [-122.4194, 37.7749],
        ...
        [-122.4312, 37.7652]
      ]
    }
    ```
-   **Validation & Constraints:**
    -   Validate that `coordinates` is a list of lists, where each inner list contains exactly two numeric values (longitude, latitude).
    -   Enforce a minimum of 2 coordinates and a maximum of 25 coordinates (to respect OSRM public API limits and prevent excessive processing time).
    -   Return `400 Bad Request` for invalid input or constraints violations.
    -   Catch `RoutingError` from `OSRMService` and return an appropriate error response (e.g., `400 Bad Request` with an error message detailing the issue).

---

## Out of Scope

-   Integration with Mapbox or other paid routing APIs.
-   Caching of calculated routes (to be considered later if performance becomes an issue).
-   Frontend changes to consume this new endpoint (handled in a separate task).
