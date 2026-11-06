import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/services/api_config.dart';

// Everything else on ApiConfig is a compile-time constant (kReleaseMode,
// kIsWeb, String.fromEnvironment), so only the values a debug/test build
// resolves to with the default dart-defines are asserted here.
void main() {
  test('points at the local backend on the desktop test host', () {
    expect(ApiConfig.baseUrl, 'http://localhost:8000/api/');
    expect(ApiConfig.baseUrl, endsWith('/'));
  });

  test('enables the DEV sign-in button but not auto-login by default', () {
    expect(ApiConfig.devLoginEnabled, isTrue);
    expect(ApiConfig.devAutoLogin, isFalse);
  });

  test('dev credentials match the backend seed defaults', () {
    expect(ApiConfig.devUsername, 'demo');
    expect(ApiConfig.devPassword, 'demo12345!');
  });

  test('Auth0 defaults are a real tenant, not the mock placeholder', () {
    expect(ApiConfig.auth0Domain, 'b1codes.us.auth0.com');
    expect(ApiConfig.auth0ClientId, isNot('YOUR_AUTH0_CLIENT_ID'));
    expect(ApiConfig.auth0Audience, 'https://api.mapmyfriends.com/');
  });

  test('third-party endpoints default to the public servers', () {
    expect(
      ApiConfig.osrmBaseUrl,
      'https://router.project-osrm.org/route/v1/driving',
    );
    // Empty means each map style keeps its own tile server.
    expect(ApiConfig.tileUrlOverride, isEmpty);
  });
}
