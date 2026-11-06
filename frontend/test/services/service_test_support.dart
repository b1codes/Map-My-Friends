import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/services/auth_service.dart';

import '../helpers/fake_http_adapter.dart';

/// Base URL every service resolves to under flutter_test on the desktop host.
const testBaseUrl = 'http://localhost:8000/api/';

/// Secure-storage keys [AuthService] writes.
const accessKey = 'access_token';
const refreshKey = 'refresh_token';
const usernameKey = 'username';

/// Reads what [AuthService] persisted into the faked secure storage.
Future<Map<String, String>> storedValues() =>
    const FlutterSecureStorage().readAll();

/// Seeds secure storage, as a previous login would have.
void seedTokens({String? access, String? refresh, String? username}) {
  FlutterSecureStorage.setMockInitialValues({
    accessKey: ?access,
    refreshKey: ?refresh,
    usernameKey: ?username,
  });
}

/// A real [AuthService] whose every Dio (the plain one and the
/// per-call authenticated ones) talks to [adapter].
AuthService authServiceOn(FakeHttpAdapter adapter) => AuthService.forTesting(
  dioFactory: (options) => Dio(options)..httpClientAdapter = adapter,
);

/// The Authorization header a request carried, if any.
String? authHeaderOf(RequestOptions request) =>
    request.headers['Authorization'] as String?;

/// Matches an [Exception] whose `toString()` is exactly `Exception: [message]`.
Matcher exceptionWith(String message) => isA<Exception>().having(
  (e) => e.toString(),
  'message',
  'Exception: $message',
);

/// Matches an [Exception] whose `toString()` starts with `Exception: [prefix]`.
Matcher exceptionStartingWith(String prefix) => isA<Exception>().having(
  (e) => e.toString(),
  'message',
  startsWith('Exception: $prefix'),
);
