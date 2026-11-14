import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import '../models/airport.dart';
import 'api_config.dart';
import 'auth_service.dart';

class AirportService {
  late final Dio _dio;
  final AuthService _authService;

  // Singleton pattern
  static final AirportService _instance = AirportService._internal();

  factory AirportService() {
    return _instance;
  }

  /// A non-singleton instance for tests: [dio] carries a fake HTTP adapter,
  /// and the auth interceptor is attached to it exactly as in production.
  @visibleForTesting
  factory AirportService.forTesting({
    required Dio dio,
    required AuthService authService,
  }) => AirportService._internal(dio: dio, authService: authService);

  AirportService._internal({Dio? dio, AuthService? authService})
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

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _authService.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        // On a 401, refresh the token and retry once.
        onError: (error, handler) =>
            _authService.retryUnauthorized(error, handler, _dio),
      ),
    );
  }

  /// Load all airports from the bundled JSON asset (for map layer).
  Future<List<Airport>> loadAirportsFromAsset() async {
    final jsonString = await rootBundle.loadString('assets/data/airports.json');
    final jsonList = json.decode(jsonString) as List<dynamic>;
    return jsonList
        .map((json) => Airport.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Fetch the nearest airports from the backend API (for profile sections).
  Future<List<Airport>> getNearestAirports(
    double lat,
    double lon, {
    int count = 3,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        'airports/nearest/',
        queryParameters: {'lat': lat, 'lon': lon, 'count': count},
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic> &&
            data['type'] == 'FeatureCollection') {
          final features = data['features'] as List;
          return features
              .map((json) => Airport.fromGeoJson(json as Map<String, dynamic>))
              .toList();
        } else if (data is List) {
          return data
              .map((json) => Airport.fromGeoJson(json as Map<String, dynamic>))
              .toList();
        }
        throw Exception('Unexpected response format');
      } else {
        throw Exception('Failed to load nearest airports');
      }
    } catch (e) {
      throw Exception('Failed to load nearest airports: $e');
    }
  }
}
