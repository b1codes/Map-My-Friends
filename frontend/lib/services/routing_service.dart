import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class RoutingService {
  final Dio _dio = Dio();

  Future<List<LatLng>> getRoute(List<LatLng> points) async {
    if (points.length < 2) return [];

    try {
      final coordinates = points
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');

      final url =
          'https://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=geojson';

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> coords =
            data['routes'][0]['geometry']['coordinates'];
        return coords
            .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
            .toList();
      }
    } catch (e) {
      developer.log('Routing error', error: e, name: 'RoutingService');
    }

    // Fallback to straight lines
    return points;
  }
}
