import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:golden_harness/golden_harness.dart';
import 'package:map_my_friends/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import '../helpers/recording_http_overrides.dart';
import 'fake_api.dart';

/// The network, for every session in the file. One instance, re-pointed at
/// each session's [FakeApi]: the app's service singletons build their HTTP
/// clients once, from whatever overrides are installed then, and keep them.
/// A fresh overrides object per session would leave them talking to the
/// first session's API.
final RecordingHttpOverrides appNetwork = RecordingHttpOverrides();

/// Call from `setUpAll`, before the first [AppSession].
///
/// Loads the app's real typefaces, so text takes the space it does on a
/// device (an overflow is a real one), and every session lays out the same
/// whatever ran before it.
Future<void> setUpAppSessions() async {
  tz.initializeTimeZones();
  await loadRealFonts();
  HttpOverrides.global = appNetwork;
}

/// One launch of the real app (`MyApp`, wired as `main.dart` wires it) on a
/// fresh device, over a fresh [FakeApi].
///
/// Secure storage holds a signed-in session unless [signedIn] is false;
/// location is granted (in Milwaukee, among the seeded friends) or declined;
/// the image picker is cancelled; links "open" and are recorded in
/// [launched].
class AppSession {
  AppSession._(this.api);

  final FakeApi api;
  RecordingHttpOverrides get http => appNetwork;
  final List<String> launched = [];

  static Future<AppSession> start(
    WidgetTester tester, {
    Size window = const Size(390, 844),
    bool located = false,
    bool signedIn = true,
    int seed = 0,
    Duration latency = Duration.zero,
  }) async {
    final session = AppSession._(FakeApi(random: Random(seed)));
    appNetwork
      ..responder = session.api.respond
      ..requests.clear()
      ..offline = false
      ..latency = latency;
    session._installPlugins();
    GeolocatorPlatform.instance = _Location(granted: located);

    FlutterSecureStorage.setMockInitialValues({
      if (signedIn) ...{
        'access_token': FakeApi.accessToken,
        'refresh_token': FakeApi.refreshToken,
        'username': 'ada',
      },
    });
    // A fresh device: getInstance() otherwise hands back the last session's
    // instance, settings and all.
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    imageCache
      ..clear()
      ..clearLiveImages();
    final prefs = await SharedPreferences.getInstance();

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = window;
    await tester.pumpWidget(MyApp(prefs: prefs));
    // The auth check reads storage, not the network, so the shell is up
    // after a second whatever the latency. Its data may still be on the way.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (signedIn) {
      expect(
        find.byType(MainScreen),
        findsOneWidget,
        reason: 'the app did not open signed in',
      );
    }
    return session;
  }

  /// The requests sent to `METHOD path`, path relative to the API root
  /// (e.g. `POST people/`).
  List<RecordedRequest> requestsTo(String method, String path) => [
    for (final r in http.requests)
      if (r.method == method && r.uri.path == '/api/$path') r,
  ];

  /// Puts the test environment back. Call before the test ends, whether it
  /// passed or not.
  void restore(WidgetTester tester) {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    _uninstallPlugins();
  }

  /// Unmounts the app and runs out the clock on whatever it scheduled
  /// (toasts, debounces, retries), so no timer outlives the test.
  static Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  }

  static const _imagePicker = MethodChannel('plugins.flutter.io/image_picker');
  static const _urlLauncher = MethodChannel('plugins.flutter.io/url_launcher');

  void _installPlugins() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      // The user opens the photo picker and cancels it.
      ..setMockMethodCallHandler(_imagePicker, (_) async => null)
      // Phone, SMS and attribution links "open" in another app.
      ..setMockMethodCallHandler(_urlLauncher, (call) async {
        final url = (call.arguments as Map<Object?, Object?>?)?['url'];
        if (call.method == 'launch') launched.add('$url');
        return true;
      });
  }

  static void _uninstallPlugins() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(_imagePicker, null)
      ..setMockMethodCallHandler(_urlLauncher, null);
  }
}

/// A device where the user answered the location prompt one way or the
/// other.
class _Location extends GeolocatorPlatform {
  _Location({required this.granted});

  final bool granted;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      granted ? LocationPermission.whileInUse : LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() => checkPermission();

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position(
    latitude: 43.0389,
    longitude: -87.9065,
    timestamp: DateTime.utc(2026, 3, 5),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
