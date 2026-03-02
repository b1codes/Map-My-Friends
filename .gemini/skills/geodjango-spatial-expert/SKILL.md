---
name: geodjango-spatial-expert
description: Expert guidance for PostGIS queries, GeoJSON serialization, and spatial indexing in GeoDjango. Use when implementing geospatial features, optimizing spatial queries, or handling GeoJSON data in the backend.
---

# GeoDjango Spatial Expert

This skill provides specialized knowledge for working with GeoDjango and PostGIS in the 'Map My Friends' project.

## Key Concepts

### Spatial Fields
- Always use `django.contrib.gis.db.models.PointField` for location coordinates.
- Set `srid=4326` (WGS 84) as the default for GPS coordinates.

### Spatial Lookups
- `distance_lte`: Filter objects within a certain distance.
- `dwithin`: More efficient than `distance_lte` if an index exists.
- `bbcontains`: Check if a point is within a bounding box.

### GeoJSON Serialization
- Use `rest_framework_gis.serializers.GeoFeatureModelSerializer` for API responses that need to follow the GeoJSON specification.
- Ensure the `id_field` and `geo_field` are correctly mapped.

### Optimization
- Ensure `SPATIAL_INDEX=True` (default) on `PointField`.
- Use `annotate(distance=Distance('location', user_point))` to include distance in query results.

## Common Workflows

### Finding Friends Nearby
```python
from django.contrib.gis.geos import Point
from django.contrib.gis.measure import D
from apps.people.models import Person

user_location = Point(-122.4194, 37.7749, srid=4326)
radius_km = 10
nearby_friends = Person.objects.filter(location__distance_lte=(user_location, D(km=radius_km)))
```

### Geocoding
- The project uses `geopy` and `Nominatim`.
- Logic is typically handled in `Person.save()` or a dedicated service.
- Always check for `location` before attempting to geocode to avoid redundant API calls.
