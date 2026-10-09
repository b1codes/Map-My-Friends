import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get baseUrl {
    if (kReleaseMode) {
      // Production URL
      return 'https://your-production-url.com/api/';
    }

    // Debug environment
    if (kIsWeb) {
      return 'http://localhost:8000/api/';
    }

    if (Platform.isAndroid) {
      // Android emulator points to 10.0.2.2 for host's localhost
      return 'http://10.0.2.2:8000/api/';
    } else if (Platform.isIOS) {
      // iOS Simulator points to localhost, but physical devices need the Mac's IP
      // 192.168.1.168 is the Mac's IP address on the local network.
      return 'http://192.168.1.168:8000/api/';
    }

    // Fallback
    return 'http://localhost:8000/api/';
  }

  static const String auth0Domain = String.fromEnvironment(
    'AUTH0_DOMAIN',
    defaultValue: 'b1codes.us.auth0.com',
  );
  static const String auth0ClientId = String.fromEnvironment(
    'AUTH0_CLIENT_ID',
    defaultValue: 'aKyq4Ew0FhtHow6vTmz4IK8WjdJPVt35',
  );
  static const String auth0Audience = String.fromEnvironment(
    'AUTH0_AUDIENCE',
    defaultValue: 'https://api.mapmyfriends.com/',
  );

  // ------------------------------------------------------------------ //
  //  LOCAL DEVELOPMENT SIGN-IN                                           //
  //                                                                      //
  //  A one-tap login as the user `make seed` creates, so an emulator or  //
  //  Chrome session can get past the login wall without typing anything. //
  //  It still calls the real token endpoint - see AuthService.loginAsDev //
  //  for why a synthetic token would be useless here.                    //
  // ------------------------------------------------------------------ //

  /// Whether the DEV sign-in affordance exists in this build.
  ///
  /// `kReleaseMode` is a compile-time constant, so this whole expression is
  /// folded by the compiler and the dev-login code is tree-shaken out of any
  /// release build. Passing `--dart-define=DEV_LOGIN=true` to a release build
  /// cannot resurrect it; the flag only exists to turn the button *off* in a
  /// debug build (`--dart-define=DEV_LOGIN=false`).
  static const bool devLoginEnabled =
      !kReleaseMode && bool.fromEnvironment('DEV_LOGIN', defaultValue: true);

  /// Skip the login screen entirely and sign in as the dev user on launch.
  ///
  /// Off by default - opt in with `--dart-define=DEV_AUTOLOGIN=true`. Useful
  /// when iterating on a screen that lives behind the auth wall, since a hot
  /// restart would otherwise drop you back at the login form.
  static const bool devAutoLogin =
      devLoginEnabled && bool.fromEnvironment('DEV_AUTOLOGIN');

  /// Credentials for the dev user. Defaults match `DEMO_USERNAME` /
  /// `DEMO_PASSWORD` in `backend/apps/common/management/commands/seed.py`;
  /// override with `--dart-define` if you seeded a different account.
  static const String devUsername = String.fromEnvironment(
    'DEV_USERNAME',
    defaultValue: 'demo',
  );
  static const String devPassword = String.fromEnvironment(
    'DEV_PASSWORD',
    defaultValue: 'demo12345!',
  );
}
