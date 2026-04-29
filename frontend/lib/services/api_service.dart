import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../models/person.dart';
import '../models/trip.dart';
import '../models/airport.dart';
import '../models/station.dart';
import 'api_config.dart';
import 'auth_service.dart';

class ApiService {
  late final Dio _dio;
  final AuthService _authService = AuthService();

  // Singleton pattern
  static final ApiService _instance = ApiService._internal();

  factory ApiService() {
    return _instance;
  }

  Dio get dio => _dio;

  ApiService._internal() {
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
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            // Try to refresh the token
            final newToken = await _authService.refreshAccessToken();
            if (newToken != null) {
              // Retry the request with new token
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

  Future<List<Person>> getPeople() async {
    try {
      final response = await _dio.get('people/');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic> &&
            data['type'] == 'FeatureCollection') {
          final features = data['features'] as List;
          return features.map((json) => Person.fromGeoJson(json)).toList();
        } else if (data is List) {
          return data.map((json) => Person.fromJson(json)).toList();
        } else {
          throw Exception('Unexpected response format');
        }
      } else {
        throw Exception('Failed to load people');
      }
    } catch (e) {
      throw Exception('Failed to load people: $e');
    }
  }

  FormData _buildFormData(
    Person person, {
    Uint8List? imageBytes,
    String? imageName,
  }) {
    final formData = FormData();

    // Add all text fields one by one
    person.toJson().forEach((key, value) {
      if (value != null) {
        formData.fields.add(MapEntry(key, value.toString()));
      }
    });

    // Add image file separately so it's properly encoded as a file upload
    if (imageBytes != null) {
      formData.files.add(
        MapEntry(
          'profile_image',
          MultipartFile.fromBytes(
            imageBytes,
            filename: imageName ?? 'person_image.png',
            contentType: DioMediaType('image', 'png'),
          ),
        ),
      );
    }

    return formData;
  }

  Future<Person> addPerson(
    Person person, {
    XFile? profileImage,
    Uint8List? imageBytes,
  }) async {
    try {
      Uint8List? bytes = imageBytes;
      if (bytes == null && profileImage != null) {
        bytes = await profileImage.readAsBytes();
      }

      final formData = _buildFormData(
        person,
        imageBytes: bytes,
        imageName: profileImage?.name,
      );

      final response = await _dio.post('people/', data: formData);
      if (response.statusCode == 201) {
        return Person.fromGeoJson(response.data);
      } else {
        throw Exception('Failed to add person');
      }
    } catch (e) {
      throw Exception('Failed to add person: $e');
    }
  }

  Future<Person> updatePerson(
    Person person, {
    XFile? profileImage,
    Uint8List? imageBytes,
  }) async {
    try {
      Uint8List? bytes = imageBytes;
      if (bytes == null && profileImage != null) {
        bytes = await profileImage.readAsBytes();
      }

      final formData = _buildFormData(
        person,
        imageBytes: bytes,
        imageName: profileImage?.name,
      );

      final response = await _dio.patch('people/${person.id}/', data: formData);
      if (response.statusCode == 200) {
        return Person.fromGeoJson(response.data);
      } else {
        throw Exception('Failed to update person');
      }
    } catch (e) {
      throw Exception('Failed to update person: $e');
    }
  }

  Future<void> deletePerson(String id) async {
    try {
      final response = await _dio.delete('people/$id/');
      if (response.statusCode != 204) {
        throw Exception('Failed to delete person');
      }
    } catch (e) {
      throw Exception('Failed to delete person: $e');
    }
  }

  // Trip methods
  Future<List<Trip>> getTrips() async {
    try {
      final response = await _dio.get('trips/');
      if (response.statusCode == 200) {
        final data = response.data;
        final results = data is Map ? data['results'] as List : data as List;
        return results
            .map((json) => Trip.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to load trips');
      }
    } catch (e) {
      throw Exception('Failed to load trips: $e');
    }
  }

  Future<Trip> createTrip(Trip trip) async {
    try {
      final response = await _dio.post('trips/', data: trip.toJson());
      if (response.statusCode == 201) {
        return Trip.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw Exception('Failed to create trip');
      }
    } catch (e) {
      throw Exception('Failed to create trip: $e');
    }
  }

  Future<Trip> updateTrip(Trip trip) async {
    try {
      if (trip.id == null) throw Exception('Trip ID is required for update');
      final response = await _dio.patch(
        'trips/${trip.id}/',
        data: trip.toJson(),
      );
      if (response.statusCode == 200) {
        return Trip.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw Exception('Failed to update trip');
      }
    } catch (e) {
      throw Exception('Failed to update trip: $e');
    }
  }

  Future<void> deleteTrip(int id) async {
    try {
      final response = await _dio.delete('trips/$id/');
      if (response.statusCode != 204) {
        throw Exception('Failed to delete trip');
      }
    } catch (e) {
      throw Exception('Failed to delete trip: $e');
    }
  }

  // Hub methods
  Future<List<Airport>> getNearestAirports(
    double lat,
    double lon, {
    int count = 5,
  }) async {
    try {
      final response = await _dio.get(
        'airports/nearest/',
        queryParameters: {'lat': lat, 'lon': lon, 'count': count},
      );
      if (response.statusCode == 200) {
        final features = response.data['features'] as List;
        return features.map((json) => Airport.fromGeoJson(json)).toList();
      } else {
        throw Exception('Failed to load nearest airports');
      }
    } catch (e) {
      throw Exception('Failed to load nearest airports: $e');
    }
  }

  Future<List<Station>> getNearestStations(
    double lat,
    double lon, {
    int count = 5,
  }) async {
    try {
      final response = await _dio.get(
        'stations/nearest/',
        queryParameters: {'lat': lat, 'lon': lon, 'count': count},
      );
      if (response.statusCode == 200) {
        final features = response.data['features'] as List;
        return features.map((json) => Station.fromGeoJson(json)).toList();
      } else {
        throw Exception('Failed to load nearest stations');
      }
    } catch (e) {
      throw Exception('Failed to load nearest stations: $e');
    }
  }
}
