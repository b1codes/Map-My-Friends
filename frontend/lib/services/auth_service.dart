import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:auth0_flutter/auth0_flutter.dart';
import 'api_config.dart';

class AuthService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 3),
    ),
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late final Auth0 _auth0;

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _usernameKey = 'username';

  // Singleton pattern
  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal() {
    _auth0 = Auth0(ApiConfig.auth0Domain, ApiConfig.auth0ClientId);
  }

  /// Get authenticated Dio instance with JWT token
  Future<Dio> _getAuthenticatedDio() async {
    final token = await getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    return Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
  }

  Future<Map<String, String>> login(String username, String password) async {
    try {
      final response = await _dio.post(
        'user/auth/token/',
        data: {'username': username, 'password': password},
      );

      if (response.statusCode == 200) {
        final accessToken = response.data['access'] as String;
        final refreshToken = response.data['refresh'] as String;

        await _storage.write(key: _accessTokenKey, value: accessToken);
        await _storage.write(key: _refreshTokenKey, value: refreshToken);
        await _storage.write(key: _usernameKey, value: username);

        return {
          'access': accessToken,
          'refresh': refreshToken,
          'username': username,
        };
      } else {
        throw Exception('Invalid credentials');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Invalid username or password');
      }
      throw Exception('Login failed: ${e.message}');
    }
  }

  /// Sign in as the locally seeded development user, skipping credential entry.
  ///
  /// This deliberately goes through the same `user/auth/token/` endpoint as a
  /// normal login instead of minting a fake token. Every screen behind the auth
  /// wall calls the API through [_getAuthenticatedDio], and Django validates
  /// those tokens with SimpleJWT - a synthetic token would only move the 401
  /// from the login screen to the map screen. What this bypasses is typing the
  /// credentials, not checking them.
  ///
  /// Requires the local stack to be running and seeded: `make up && make seed`.
  Future<Map<String, String>> loginAsDev() async {
    if (!ApiConfig.devLoginEnabled) {
      // Unreachable in release builds - the caller is tree-shaken away - but
      // keep the guard so an accidental call fails loudly rather than
      // attempting a login with hardcoded credentials.
      throw Exception('DEV sign-in is not available in this build.');
    }

    try {
      return await login(ApiConfig.devUsername, ApiConfig.devPassword);
    } catch (e) {
      final reason = e.toString().replaceFirst('Exception: ', '');
      throw Exception(
        'DEV sign-in failed for "${ApiConfig.devUsername}" at '
        '${ApiConfig.baseUrl}\n'
        'Start and seed the local stack: make up && make seed\n'
        '($reason)',
      );
    }
  }

  Future<Map<String, String>> loginWithAuth0({String? connection}) async {
    // If we're using the placeholder Client ID, run in mock mode
    if (ApiConfig.auth0ClientId == 'YOUR_AUTH0_CLIENT_ID') {
      await Future.delayed(const Duration(milliseconds: 800));
      final mockUsername = connection == 'google-oauth2'
          ? 'google_user'
          : (connection == 'apple' ? 'apple_user' : 'auth0_user');
      final mockToken =
          'mock_auth0_jwt_token_${mockUsername}_${DateTime.now().millisecondsSinceEpoch}';

      await _storage.write(key: _accessTokenKey, value: mockToken);
      await _storage.write(key: _refreshTokenKey, value: 'mock_refresh_token');
      await _storage.write(key: _usernameKey, value: mockUsername);

      return {
        'access': mockToken,
        'refresh': 'mock_refresh_token',
        'username': mockUsername,
      };
    }

    try {
      final credentials = await _auth0
          .webAuthentication(scheme: 'demo')
          .login(
            audience: ApiConfig.auth0Audience,
            scopes: {'openid', 'profile', 'email', 'offline_access'},
            parameters: connection != null ? {'connection': connection} : {},
          );

      final accessToken = credentials.accessToken;
      final refreshToken = credentials.refreshToken ?? '';

      // Extract username/nickname from user claims
      final userProfile = credentials.user;
      final username =
          userProfile.nickname ?? userProfile.name ?? userProfile.email ?? '';

      await _storage.write(key: _accessTokenKey, value: accessToken);
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
      await _storage.write(key: _usernameKey, value: username);

      return {
        'access': accessToken,
        'refresh': refreshToken,
        'username': username,
      };
    } catch (e) {
      throw Exception('Auth0 Login failed: $e');
    }
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
    required String passwordConfirm,
    String? firstName,
    String? lastName,
    String? firstNameHp,
  }) async {
    try {
      final response = await _dio.post(
        'user/auth/register/',
        data: {
          'username': username,
          'email': email,
          'password': password,
          'password_confirm': passwordConfirm,
          'first_name': firstName,
          'last_name': lastName,
          'first_name_hp': firstNameHp,
        }..removeWhere((key, value) => value == null),
      );

      if (response.statusCode != 201) {
        throw Exception('Registration failed');
      }
    } on DioException catch (e) {
      if (e.response?.data != null) {
        final errors = e.response!.data as Map<String, dynamic>;
        final errorMessage = errors.entries
            .map((e) => '${e.key}: ${(e.value as List).join(', ')}')
            .join('\n');
        throw Exception(errorMessage);
      }
      throw Exception('Registration failed: ${e.message}');
    }
  }

  Future<void> requestPasswordReset(String email) async {
    try {
      await _dio.post('user/auth/password-reset/', data: {'email': email});
    } on DioException catch (e) {
      throw Exception('Password reset request failed: ${e.message}');
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _usernameKey);
  }

  Future<Map<String, String>?> getStoredTokens() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    final username = await _storage.read(key: _usernameKey);

    if (accessToken != null && refreshToken != null) {
      return {
        'access': accessToken,
        'refresh': refreshToken,
        'username': username ?? '',
      };
    }
    return null;
  }

  Future<String?> refreshAccessToken() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) return null;

    try {
      final response = await _dio.post(
        'user/auth/token/refresh/',
        data: {'refresh': refreshToken},
      );

      if (response.statusCode == 200) {
        final newAccessToken = response.data['access'] as String;
        await _storage.write(key: _accessTokenKey, value: newAccessToken);
        return newAccessToken;
      }
    } catch (e) {
      // Token refresh failed, user needs to login again
      await logout();
    }
    return null;
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: _accessTokenKey);
  }

  // ============ Profile Methods ============

  /// Get the current user's profile
  Future<Map<String, dynamic>> getProfile() async {
    try {
      final dio = await _getAuthenticatedDio();
      final response = await dio.get('user/profile/');

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to load profile');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Authentication required');
      }
      throw Exception('Failed to load profile: ${e.message}');
    }
  }

  /// Update the current user's profile
  Future<Map<String, dynamic>> updateProfile({
    String? firstName,
    String? lastName,
    String? city,
    String? state,
    String? country,
    String? street,
    String? birthDate,
    String? phoneNumber,
    String? pinColor,
    String? pinStyle,
    String? pinIconType,
    String? pinEmoji,
    String? distanceUnit,
  }) async {
    try {
      final dio = await _getAuthenticatedDio();
      final data = <String, dynamic>{};

      if (firstName != null) data['first_name'] = firstName;
      if (lastName != null) data['last_name'] = lastName;
      if (city != null) data['city'] = city;
      if (state != null) data['state'] = state;
      if (country != null) data['country'] = country;
      if (street != null) data['street'] = street;
      if (birthDate != null) data['birth_date'] = birthDate;
      if (phoneNumber != null) data['phone_number'] = phoneNumber;
      if (pinColor != null) data['pin_color'] = pinColor;
      if (pinStyle != null) data['pin_style'] = pinStyle;
      if (pinIconType != null) data['pin_icon_type'] = pinIconType;
      if (pinEmoji != null) data['pin_emoji'] = pinEmoji;
      if (distanceUnit != null) data['distance_unit'] = distanceUnit;

      final response = await dio.patch('user/profile/', data: data);

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to update profile');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Authentication required');
      }
      throw Exception('Failed to update profile: ${e.message}');
    }
  }

  /// Upload a profile image
  Future<Map<String, dynamic>> uploadProfileImage(
    Uint8List bytes,
    String imageName,
  ) async {
    try {
      final dio = await _getAuthenticatedDio();

      final formData = FormData();
      formData.files.add(
        MapEntry(
          'profile_image',
          MultipartFile.fromBytes(
            bytes,
            filename: imageName,
            contentType: DioMediaType('image', 'png'),
          ),
        ),
      );

      final response = await dio.patch(
        'user/profile/',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to upload profile image');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Authentication required');
      }
      throw Exception('Failed to upload profile image: ${e.message}');
    }
  }
}
