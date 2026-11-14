import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import '../models/station.dart';
import 'api_config.dart';
import 'auth_service.dart';

class StationService {
  late final Dio _dio;
  final AuthService _authService;

  // Singleton pattern
  static final StationService _instance = StationService._internal();

  factory StationService() {
    return _instance;
  }

  /// A non-singleton instance for tests: [dio] carries a fake HTTP adapter,
  /// and the auth interceptor is attached to it exactly as in production.
  @visibleForTesting
  factory StationService.forTesting({
    required Dio dio,
    required AuthService authService,
  }) => StationService._internal(dio: dio, authService: authService);

  StationService._internal({Dio? dio, AuthService? authService})
    : _authService = authService ?? AuthService() {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: ApiConfig.baseUrl,
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 3),
          ),
        );

    _dio.interceptors.add(_authService.authInterceptor(_dio));
  }

  /// Load all stations from the bundled JSON asset (for map layer).
  Future<List<Station>> loadStationsFromAsset() async {
    final jsonString = await rootBundle.loadString('assets/data/stations.json');
    final jsonList = json.decode(jsonString) as List<dynamic>;
    return jsonList
        .map((json) => Station.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Fetch the nearest stations from the backend API.
  Future<List<Station>> getNearestStations(
    double lat,
    double lon, {
    int count = 3,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        'stations/nearest/',
        queryParameters: {'lat': lat, 'lon': lon, 'count': count},
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic> &&
            data['type'] == 'FeatureCollection') {
          final features = data['features'] as List;
          return features
              .map((json) => Station.fromGeoJson(json as Map<String, dynamic>))
              .toList();
        } else if (data is List) {
          return data
              .map((json) => Station.fromGeoJson(json as Map<String, dynamic>))
              .toList();
        }
        throw Exception('Unexpected response format');
      } else {
        throw Exception('Failed to load nearest stations');
      }
    } catch (e) {
      throw Exception('Failed to load nearest stations: $e');
    }
  }
}
