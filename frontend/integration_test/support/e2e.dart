// Shared harness for the E2E journeys.
//
// The journeys drive the real app (lib/main.dart) in Chrome against the real
// API on the E2E stack (docker-compose.e2e.yml). Nothing in the app is
// mocked; the only stand-ins are the third-party services, answered by
// docker/e2e-stubs. Run them with `make e2e` (scripts/e2e.sh), which builds the
// app with the dart-defines read below.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:map_my_friends/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

/// The E2E API, e.g. `http://localhost:8100/api/`. The app reads the same
/// define (ApiConfig.baseUrl), so the harness and the app share one backend.
const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// The third-party stub server, e.g. `http://localhost:8190`.
const String stubsUrl = String.fromEnvironment('E2E_STUBS_URL');

/// Password every journey user signs up with. Long and mixed so Django's
/// password validators accept it.
const String journeyPassword = 'Journey-pass-2026!';

/// How long to wait for the app to reach an expected screen. Generous: the
/// first API call after a cold start also warms Django and the emulator.
const Duration defaultTimeout = Duration(seconds: 30);

/// The window every journey sees, in logical pixels, whatever the browser's
/// real viewport is. Headless Chrome's viewport for the same window size
/// differs by platform (657px tall on macOS, 600px on the Linux CI runner),
/// and the layout differs between those heights, so journeys pin one
/// laptop-sized window. scripts/e2e.sh opens the browser
/// larger than this so the whole of it is visible in failure screenshots.
const Size journeyWindow = Size(1280, 720);

IntegrationTestWidgetsFlutterBinding get binding =>
    IntegrationTestWidgetsFlutterBinding.instance;

/// Call at the top of every journey file's `main`. Safe to call more than
/// once, as all_test.dart does by running several files' `main`s.
void setUpE2E() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (apiBaseUrl.isEmpty || stubsUrl.isEmpty) {
    // Without the defines the app would talk to the development stack on
    // :8000 and fill it with journey users. Refuse rather than do that.
    throw StateError(
      'API_BASE_URL and E2E_STUBS_URL must be set. Run the journeys with '
      '`make e2e`, which passes them.',
    );
  }
}

/// A journey test: a [testWidgets] that saves a screenshot when it fails, so
/// a CI failure shows the screen the app was actually on.
///
/// [skip] is the reason a journey is switched off, e.g. 'Known bug: ...
/// (ClickUp link)'. A journey that exposes a bug keeps asserting the right
/// behaviour and is skipped until the bug is fixed, rather than rewritten to
/// expect the wrong one.
void journey(
  String description,
  Future<void> Function(WidgetTester) body, {
  String? skip,
}) {
  if (skip != null) debugPrint('Skipping "$description": $skip');
  testWidgets(skip: skip != null, description, (tester) async {
    // Navigation is found by semantics label (see [tab]), so the semantics
    // tree must be built, as it is for a screen-reader user.
    final semantics = tester.ensureSemantics();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = journeyWindow;
    addTearDown(tester.view.reset);
    try {
      await body(tester);
    } catch (_) {
      await _screenshot(description);
      rethrow;
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _screenshot(String description) async {
  final name = description
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  try {
    await binding.takeScreenshot(name);
  } catch (e) {
    debugPrint('Could not save a failure screenshot: $e');
  }
}

// --------------------------------------------------------------------------
// App lifecycle
// --------------------------------------------------------------------------

/// Starts the app the way a user opens it.
///
/// By default it first clears everything the app keeps on the device
/// (tokens in secure storage, settings in shared preferences), so each
/// journey starts as a first visit. Pass [keepDeviceState] to model the user
/// coming back to an app they already used.
Future<void> launchApp(
  WidgetTester tester, {
  bool keepDeviceState = false,
}) async {
  // Tear down the previous launch first. runApp with a root of the same type
  // would update the old tree in place: its blocs (signed in or not), pushed
  // routes and screen state would all survive, so nothing would relaunch.
  await tester.pumpWidget(const SizedBox.shrink());

  if (!keepDeviceState) {
    await const FlutterSecureStorage().deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
  // A relaunch is a new page with nothing decoded yet. Without this, images
  // (map tiles, avatars) from an earlier journey come from Flutter's
  // in-memory cache and never reach the server.
  imageCache
    ..clear()
    ..clearLiveImages();
  // Location is the one browser capability that differs between machines:
  // headless Chrome has none on macOS but reports a position on the Linux CI
  // runner, which moves the map away from the people a journey seeded. Every
  // journey runs as a user who declined the location prompt; the prompt
  // itself is on the manual QA checklist.
  GeolocatorPlatform.instance = _LocationDeclined();
  app.main();
  // The first frames are the auth check; let it start before callers wait.
  await tester.pump(const Duration(milliseconds: 100));
}

/// A device where the user answered "Don't allow" to the location prompt.
class _LocationDeclined extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.denied;
}

/// Pumps frames until [finder] matches, or fails after [timeout].
///
/// The app never settles (the ambient background and pulse indicators
/// animate forever), so `pumpAndSettle` would time out; this is the
/// replacement. On timeout the failure lists the text on screen, which is
/// usually enough to see where the journey went wrong.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = defaultTimeout,
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail(
    'Timed out after ${timeout.inSeconds}s waiting for '
    '${reason ?? finder.describeMatch(Plurality.one)}.\n'
    'Text on screen:\n${visibleText().map((t) => '  - $t').join('\n')}',
  );
}

/// Pumps frames until [finder] no longer matches.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = defaultTimeout,
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) return;
  }
  fail(
    'Timed out after ${timeout.inSeconds}s waiting for '
    '${reason ?? finder.describeMatch(Plurality.one)} to go away.\n'
    'Text on screen:\n${visibleText().map((t) => '  - $t').join('\n')}',
  );
}

/// Pumps for a fixed time, for animations a journey must let finish (route
/// transitions, sheets) before the next tap lands.
Future<void> settle(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 600),
]) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Every non-empty [Text] currently built, in tree order.
List<String> visibleText() => find
    .byType(Text)
    .evaluate()
    .map(
      (e) =>
          (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText(),
    )
    .whereType<String>()
    .where((t) => t.trim().isNotEmpty)
    .toList();

// --------------------------------------------------------------------------
// Interactions
// --------------------------------------------------------------------------

/// Scrolls [finder] into view if needed, then taps it.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Taps the widget showing exactly [text].
Future<void> tapText(WidgetTester tester, String text) =>
    tapOn(tester, find.text(text));

/// The text field whose label (or hint) is [label].
///
/// `.first` because a form can repeat a label on purpose: the sign-up form's
/// hidden honeypot is labelled 'First Name', after the real one.
Finder field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField)).first;

/// Replaces the text in the field labelled [label].
Future<void> enterField(WidgetTester tester, String label, String text) async {
  final target = field(label);
  await pumpUntil(tester, target, reason: 'a field labelled "$label"');
  await tester.ensureVisible(target);
  await tester.enterText(target, text);
  await tester.pump(const Duration(milliseconds: 50));
}

/// A toast (GlassToast) showing [message], or a message containing it.
Finder toast(String message) => find.descendant(
  of: find.byType(SnackBar),
  matching: find.textContaining(message),
);

// --------------------------------------------------------------------------
// The app's own screens
// --------------------------------------------------------------------------

/// The navigation tab labelled [name] ('Map', 'People', 'Pulse', 'Trips',
/// 'Me'). The rail (wide windows) and the bottom bar (narrow ones) carry the
/// same semantics label, so journeys work at any window size.
///
/// Matched by prefix: the label merges with the tab's visible text below it.
Finder tab(String name) => find.bySemanticsLabel(RegExp('^$name Tab'));

/// The signed-in shell: any screen with the navigation tabs.
Finder get mainShell => tab('Map');

/// The sign-in form.
Finder get loginScreen => find.widgetWithText(FilledButton, 'Sign In');

Future<void> goToTab(WidgetTester tester, String name) async {
  await tapOn(tester, tab(name));
  await settle(tester);
}

/// A person's pin on the map (PersonMapMarker's semantics label).
Finder pinOf(String fullName) => find.bySemanticsLabel('Friend: $fullName');

/// Leaves a pushed screen through its header's back button.
Future<void> goBack(WidgetTester tester) async {
  await tapOn(tester, find.byTooltip('Back'));
  await settle(tester);
}

/// Signs in through the login form and waits for the main shell.
Future<void> signInThroughUi(
  WidgetTester tester,
  String username, {
  String password = journeyPassword,
}) async {
  await pumpUntil(tester, loginScreen);
  await enterField(tester, 'Username', username);
  await enterField(tester, 'Password', password);
  await tapOn(tester, loginScreen);
  await pumpUntil(tester, mainShell, reason: 'the main shell after sign-in');
  await settle(tester);
}

/// Opens the app as a returning [user] who is already signed up: a clean
/// device, then the real sign-in form.
Future<void> launchSignedIn(WidgetTester tester, JourneyUser user) async {
  await launchApp(tester);
  await signInThroughUi(tester, user.username);
}

// --------------------------------------------------------------------------
// Direct API access, for arranging state a journey isn't about
// --------------------------------------------------------------------------

/// A user created for one journey. Names are unique per run, and every run
/// starts on an empty stack, so journeys never see each other's data.
class JourneyUser {
  JourneyUser._(this.username, this.email);

  final String username;
  final String email;

  static int _counter = 0;

  /// A fresh, never-registered identity (nothing is created yet).
  factory JourneyUser.fresh(String prefix) {
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final name = 'e2e_${prefix}_$stamp${_counter++}';
    return JourneyUser._(name, '$name@example.com');
  }

  /// Signs up a fresh user through the API, skipping the sign-up form.
  static Future<JourneyUser> registered(
    String prefix, {
    String? firstName,
    String? lastName,
  }) async {
    final user = JourneyUser.fresh(prefix);
    await E2EApi.anonymous().post(
      'user/auth/register/',
      data: {
        'username': user.username,
        'email': user.email,
        'password': journeyPassword,
        'password_confirm': journeyPassword,
        'first_name': ?firstName,
        'last_name': ?lastName,
      },
    );
    return user;
  }

  /// Adds a person to this user's account through the API. [city] must be
  /// one the stub geocoder knows (CITIES in docker/e2e-stubs/server.py). The
  /// default is the map's fallback centre, so the pin is on screen without
  /// location access.
  Future<void> addPerson({
    required String firstName,
    required String lastName,
    String city = 'San Francisco',
    String state = 'CA',
    String country = 'USA',
  }) async {
    await (await api()).post(
      'people/',
      data: {
        'first_name': firstName,
        'last_name': lastName,
        'city': city,
        'state': state,
        'country': country,
        'tag': 'FRIEND',
      },
    );
  }

  Dio? _api;

  /// An API client signed in as this user. Signs in once per user: sign-ins
  /// count against the API's anonymous throttle like any other.
  Future<Dio> api() async {
    if (_api != null) return _api!;
    final response = await E2EApi.anonymous().post(
      'user/auth/token/',
      data: {'username': username, 'password': journeyPassword},
    );
    return _api = E2EApi.authenticated(response.data['access'] as String);
  }
}

class E2EApi {
  /// For sign-up and sign-in. These are throttled per client address (sign-up
  /// to 10 a minute), and a full run arranges more users than that, so a 429
  /// is waited out and retried. Journeys that exercise the UI's own sign-up
  /// and sign-in still meet the real throttle.
  static Dio anonymous() =>
      Dio(BaseOptions(baseUrl: apiBaseUrl))
        ..interceptors.add(_WaitOutThrottle());

  static Dio authenticated(String accessToken) => Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      headers: {'Authorization': 'Bearer $accessToken'},
    ),
  );

  /// The third-party calls the stub server has answered since [clearStubLog].
  static Future<List<Map<String, dynamic>>> stubLog() async {
    final response = await Dio().get('$stubsUrl/_stub/requests');
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  static Future<void> clearStubLog() =>
      Dio().delete('$stubsUrl/_stub/requests');
}

/// Retries a throttled (429) request after the wait DRF reports.
///
/// The wait has to come from the body ("Expected available in 42 seconds."):
/// the browser hides the Retry-After header of a cross-origin response.
class _WaitOutThrottle extends Interceptor {
  static const int _maxAttempts = 4;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attempt = (options.extra['throttleAttempt'] as int?) ?? 1;
    if (err.response?.statusCode != 429 || attempt >= _maxAttempts) {
      return handler.next(err);
    }
    final detail = '${err.response?.data}';
    final seconds =
        int.tryParse(
          RegExp(r'available in (\d+) second').firstMatch(detail)?.group(1) ??
              '',
        ) ??
        15;
    debugPrint('Throttled on ${options.path}; retrying in ${seconds + 1}s.');
    await Future<void>.delayed(Duration(seconds: seconds + 1));
    options.extra['throttleAttempt'] = attempt + 1;
    try {
      handler.resolve(await E2EApi.anonymous().fetch(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
