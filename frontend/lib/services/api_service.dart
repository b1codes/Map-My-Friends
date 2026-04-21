import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../models/person.dart';
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
}
