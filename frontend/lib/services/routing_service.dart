import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip.dart';

class RoutingService {
  final Dio _dio = Dio();

  /// Fetches a hybrid route based on stop types.
  /// - Friend -> Friend: Driving route via OSRM.
  /// - Any other combination: Straight line.
  /// - Fallback: Straight line on OSRM failure.
  Future<List<LatLng>> getRoute(List<TripStop> stops) async {
    if (stops.length < 2) return [];

    List<LatLng> fullPath = [];

    for (int i = 0; i < stops.length - 1; i++) {
      final start = stops[i];
      final end = stops[i + 1];

      // Segment Friend -> Friend: Request OSRM v1/driving route.
      if (start.person != null && end.person != null) {
        final segmentPoints = await _fetchOSRMRoute(start.location, end.location);
        if (segmentPoints.isNotEmpty) {
          // Add segment points, skipping the first one if it duplicates the last point of fullPath
          if (fullPath.isNotEmpty) {
            fullPath.addAll(segmentPoints.skip(1));
          } else {
            fullPath.addAll(segmentPoints);
          }
          continue;
        }
      }

      // Segment involves Airport/Station or OSRM failed: Straight line fallback
      if (fullPath.isEmpty) {
        fullPath.add(start.location);
      }
      fullPath.add(end.location);
    }

    return fullPath;
  }

  Future<List<LatLng>> _fetchOSRMRoute(LatLng start, LatLng end) async {
    try {
      final coordinates = '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';
      final url = 'https://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=geojson';

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final List<dynamic> coords = data['routes'][0]['geometry']['coordinates'];
          return coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
        }
      }
    } catch (e) {
      developer.log('OSRM segment error', error: e, name: 'RoutingService');
    }
    return [];
  }
}
