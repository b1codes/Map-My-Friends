import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/airport.dart';
import 'api_config.dart';
import 'auth_service.dart';

class AirportService {
  late final Dio _dio;
  final AuthService _authService = AuthService();

  // Singleton pattern
  static final AirportService _instance = AirportService._internal();

  factory AirportService() {
    return _instance;
  }

  AirportService._internal() {
    _dio = Dio(
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
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            final newToken = await _authService.refreshAccessToken();
            if (newToken != null) {
              error.requestOptions.headers['Authorization'] =
                  'Bearer $newToken';
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  /// Load all airports from the bundled JSON asset (for map layer).
  Future<List<Airport>> loadAirportsFromAsset() async {
    final jsonString = await rootBundle.loadString('assets/data/airports.json');
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((json) => Airport.fromJson(json)).toList();
  }

  /// Fetch the nearest airports from the backend API (for profile sections).
  Future<List<Airport>> getNearestAirports(
    double lat,
    double lon, {
    int count = 3,
  }) async {
    try {
      final response = await _dio.get(
        'airports/nearest/',
        queryParameters: {'lat': lat, 'lon': lon, 'count': count},
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic> &&
            data['type'] == 'FeatureCollection') {
          final features = data['features'] as List;
          return features.map((json) => Airport.fromGeoJson(json)).toList();
        } else if (data is List) {
          return data.map((json) => Airport.fromGeoJson(json)).toList();
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
