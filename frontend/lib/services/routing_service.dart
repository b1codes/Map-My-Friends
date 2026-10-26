import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:latlong2/latlong.dart';
import '../models/trip.dart';
import 'api_config.dart';

class RoutingService {
  /// A plain Dio, deliberately not `ApiService.dio`: OSRM is a public
  /// third-party host, and the API client's interceptor would attach the
  /// signed-in user's bearer token (and retry 401s through a token refresh).
  final Dio _dio;

  RoutingService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  @visibleForTesting
  Dio get dio => _dio;

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

      // Segment between people-only stops: Request OSRM v1/driving route.
      // (Segments involving Airport/Station are assumed to be flight/train - straight lines)
      final startIsPersonOnly =
          start.people.isNotEmpty &&
          start.airport == null &&
          start.station == null;
      final endIsPersonOnly =
          end.people.isNotEmpty && end.airport == null && end.station == null;

      if (startIsPersonOnly && endIsPersonOnly) {
        final segmentPoints = await _fetchOSRMRoute(
          start.location,
          end.location,
        );
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
      final coordinates =
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';
      final url =
          '${ApiConfig.osrmBaseUrl}/$coordinates?overview=full&geometries=geojson';

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final List<dynamic> coords =
              data['routes'][0]['geometry']['coordinates'];
          return coords
              .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
              .toList();
        }
      }
    } catch (e) {
      developer.log('OSRM segment error', error: e, name: 'RoutingService');
    }
    return [];
  }
}
