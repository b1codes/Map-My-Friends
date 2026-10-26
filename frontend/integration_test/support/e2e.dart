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

late final IntegrationTestWidgetsFlutterBinding binding;

/// Call once at the top of every journey file's `main`.
void setUpE2E() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
void journey(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    // Navigation is found by semantics label (see [tab]), so the semantics
    // tree must be built, as it is for a screen-reader user.
    final semantics = tester.ensureSemantics();
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
  if (!keepDeviceState) {
    await const FlutterSecureStorage().deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
  app.main();
  // The first frames are the auth check; let it start before callers wait.
  await tester.pump(const Duration(milliseconds: 100));
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

  /// An API client signed in as this user.
  Future<Dio> api() async {
    final response = await E2EApi.anonymous().post(
      'user/auth/token/',
      data: {'username': username, 'password': journeyPassword},
    );
    return E2EApi.authenticated(response.data['access'] as String);
  }
}

class E2EApi {
  static Dio anonymous() => Dio(BaseOptions(baseUrl: apiBaseUrl));

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
