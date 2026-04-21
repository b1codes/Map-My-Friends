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