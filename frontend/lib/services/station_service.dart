import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../models/station.dart';
import 'api_config.dart';
import 'auth_service.dart';

class StationService {
  late final Dio _dio;
  final AuthService _authService = AuthService();

  // Singleton pattern
  static final StationService _instance = StationService._internal();

  factory StationService() {
    return _instance;
  }

  StationService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 3),
      ),
    );

    // Add auth interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _authService.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );
  }

  /// Load all stations from the bundled JSON asset (for map layer).
  Future<List<Station>> loadStationsFromAsset() async {
    final jsonString = await rootBundle.loadString('assets/data/stations.json');
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((json) => Station.fromJson(json)).toList();
  }

  /// Fetch the nearest stations from the backend API.
  Future<List<Station>> getNearestStations(
    double lat,
    double lon, {
    int count = 3,
  }) async {
    try {
      final response = await _dio.get(
        'stations/nearest/',
        queryParameters: {'lat': lat, 'lon': lon, 'count': count},
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic> &&
            data['type'] == 'FeatureCollection') {
          final features = data['features'] as List;
          return features.map((json) => Station.fromGeoJson(json)).toList();
        } else if (data is List) {
          return data.map((json) => Station.fromGeoJson(json)).toList();
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
