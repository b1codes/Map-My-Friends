/// The widget-test monkey: the real app, wired exactly as `main.dart` wires
/// it (real blocs, real services, real Dio and interceptors), hammered by a
/// seeded random user until something throws, overflows or asks the API for
/// a route it doesn't have.
///
/// Nothing in `lib/` is replaced. The network underneath is in memory
/// ([FakeApi] behind [RecordingHttpOverrides]), and the plugins answer as a
/// device would: secure storage holds a signed-in session, location is
/// granted or declined, the image picker is cancelled, and links "open".
///
/// ```sh
/// make monkey                                    # the PR run
/// make monkey MONKEY_SEED=42 MONKEY_SESSIONS=1    # one seed
/// make monkey MONKEY_SEED=random MONKEY_MINUTES=25   # the nightly run
///
/// It runs only with `--dart-define=MONKEY=true` (which `make monkey` and
/// CI pass), so the main suite and its coverage leave it out; it has its own
/// CI job.
/// ```
///
/// Each session is one app launch with its own seed (the base seed plus its
/// index), so a failure reproduces with that seed alone. A failing session
/// prints the seed, the command and the last actions, and writes the whole
/// log and a screenshot to `build/monkey/`. See docs/testing.md (Monkey and
/// fuzz tests).
library;

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

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
import 'known_gaps.dart';
import 'monkey.dart';

/// The seed the PR run uses, so it's the same run every time. 'random'
/// draws one (the nightly run); either way it's printed.
const _seedDefine = String.fromEnvironment(
  'MONKEY_SEED',
  defaultValue: '20261108',
);

/// App launches per run, and actions per launch.
const _sessions = int.fromEnvironment('MONKEY_SESSIONS', defaultValue: 4);
const _steps = int.fromEnvironment('MONKEY_STEPS', defaultValue: 150);

/// A real-time budget for the whole run, in minutes. When set, sessions
/// keep coming (up to [_maxSessions]) until it's spent. 0 means "run
/// [_sessions] and stop".
const _minutes = int.fromEnvironment('MONKEY_MINUTES');
const _maxSessions = 10000;

/// Triage mode: run every session to the end, collecting distinct problems
/// instead of failing, and write them to build/monkey/survey.txt.
const _survey = bool.fromEnvironment('MONKEY_SURVEY');

final int _baseSeed = _seedDefine == 'random'
    ? Random().nextInt(1 << 31)
    : int.parse(_seedDefine);

final DateTime? _deadline = _minutes == 0
    ? null
    : DateTime.now().add(const Duration(minutes: _minutes));

final Directory _outDir = Directory('build/monkey');

/// The network, for the whole run. One instance, re-pointed at each
/// session's [FakeApi]: the app's service singletons build their HTTP
/// clients once, from whatever overrides are installed then, and keep them.
/// A fresh overrides object per session would leave them talking to the
/// first session's API.
final RecordingHttpOverrides _http = RecordingHttpOverrides();

/// Off unless asked for: see the library comment.
const _enabled = bool.fromEnvironment('MONKEY');

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    tz.initializeTimeZones();
    // The app's real typefaces, loaded before the first session: text takes
    // the space it does on a device (so overflows are real ones), and every
    // session lays out the same whatever ran before it, so a seed replays
    // alone exactly as it ran in the batch.
    await loadRealFonts();
    HttpOverrides.global = _http;
    // ignore: avoid_print
    print(
      'Monkey: base seed $_baseSeed, '
      '${_minutes == 0 ? '$_sessions sessions' : 'up to $_minutes minutes'}, '
      '$_steps actions each.',
    );
  });

  final count = !_enabled ? 1 : (_minutes == 0 ? _sessions : _maxSessions);
  for (var i = 0; i < count; i++) {
    final seed = _baseSeed + i;
    testWidgets(
      'monkey session seed $seed',
      (tester) => _session(tester, seed),
      // Hangs fail rather than stall CI: a session of 150 actions takes
      // about 10 seconds.
      timeout: const Timeout(Duration(minutes: 5)),
      skip: !_enabled,
    );
  }
}

Future<void> _session(WidgetTester tester, int seed) async {
  final deadline = _deadline;
  if (deadline != null && DateTime.now().isAfter(deadline)) return;

  final random = Random(seed);
  final semantics = tester.ensureSemantics();
  final api = FakeApi(random: Random(seed));
  _http
    ..responder = api.respond
    ..requests.clear()
    ..offline = false
    ..latency = Duration.zero;
  final http = _http;
  final launched = <String>[];
  _installPlugins(launched);
  final located = random.nextBool();
  GeolocatorPlatform.instance = _Location(granted: located);

  FlutterSecureStorage.setMockInitialValues({
    'access_token': FakeApi.accessToken,
    'refresh_token': FakeApi.refreshToken,
    'username': 'ada',
  });
  // A fresh device: getInstance() otherwise hands back the last session's
  // instance, settings and all, and the seed no longer replays on its own.
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues({});
  imageCache
    ..clear()
    ..clearLiveImages();
  final prefs = await SharedPreferences.getInstance();

  final window = monkeyWindows[random.nextInt(monkeyWindows.length)];
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = window;

  late final Monkey monkey;
  var signedOutFor = 0;
  monkey = Monkey(
    tester,
    seed: seed,
    extraActions: [
      MonkeyAction('network off or on', 1, (_) async {
        http.offline = !http.offline;
        return http.offline ? 'network: offline' : 'network: back online';
      }),
      MonkeyAction('network speed', 1, (m) async {
        const speeds = [
          Duration.zero,
          Duration(milliseconds: 300),
          Duration(seconds: 3),
        ];
        http.latency = speeds[m.random.nextInt(speeds.length)];
        return 'network: ${http.latency.inMilliseconds}ms per reply';
      }),
    ],
    knownGaps: knownGaps,
    survey: _survey,
    invariants: [
      (_) => api.unknownRoutes.isEmpty
          ? null
          : 'the app called routes the API does not have: '
                '${api.unknownRoutes.toSet().join(', ')}',
    ],
    // Signing out is fair game, but random typing never signs back in. After
    // a few steps on the login screen, sign in the way a user would, so the
    // rest of the session still explores the app.
    recover: (m) async {
      final signIn = find.widgetWithText(FilledButton, 'Sign In');
      if (signIn.evaluate().isEmpty) {
        signedOutFor = 0;
        return null;
      }
      if (++signedOutFor < 8) return null;
      signedOutFor = 0;
      http.offline = false;
      final fields = find.byType(TextFormField);
      if (fields.evaluate().length < 2) return null;
      await tester.enterText(fields.at(0), 'ada');
      await tester.enterText(fields.at(1), 'Analytical-Engine-1843');
      await tester.ensureVisible(signIn);
      await tester.pump();
      await tester.tap(signIn, warnIfMissed: false);
      return 'sign back in as ada';
    },
  );

  final header =
      'seed $seed, window ${window.width.toInt()}×${window.height.toInt()}, '
      'location ${located ? 'granted' : 'declined'}';
  try {
    await tester.pumpWidget(MyApp(prefs: prefs));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byType(MainScreen),
      findsOneWidget,
      reason: 'the app did not open signed in',
    );
    await monkey.run(steps: _steps, until: deadline);
    await monkey.settle();
    if (_survey) {
      _appendSurvey(seed, monkey);
      _writeLog(seed, [header, ...monkey.log], http, launched);
    }
    if (monkey.knownGapHits.isNotEmpty) {
      // ignore: avoid_print
      print(
        'Monkey session $seed hit known gaps: '
        '${monkey.knownGapHits.entries.map((e) => '${e.key.task} ×${e.value}').join(', ')}',
      );
    }
  } catch (_) {
    await _saveFailure(tester, seed, [header, ...monkey.log], http, launched);
    rethrow;
  } finally {
    monkey.reset();
    tester.view.reset();
    semantics.dispose();
    _uninstallPlugins();
  }
  // Unmount, and run out the clock on whatever the app scheduled (toasts,
  // debounces, retries), so no timer outlives the session.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 30));
}

void _appendSurvey(int seed, Monkey monkey) {
  _outDir.createSync(recursive: true);
  final file = File('${_outDir.path}/survey.txt');
  final buffer = StringBuffer();
  for (final MapEntry(:key, :value) in monkey.findings.entries) {
    buffer
      ..writeln('=== $key')
      ..writeln('seed $seed, steps ${value.steps.join(', ')}')
      ..writeln(value.report)
      ..writeln();
  }
  for (final MapEntry(:key, :value) in monkey.knownGapHits.entries) {
    buffer.writeln('=== KNOWN ${key.task} (${key.what}) seed $seed ×$value');
  }
  if (buffer.isNotEmpty) {
    file.writeAsStringSync(buffer.toString(), mode: FileMode.append);
  }
}

File _writeLog(
  int seed,
  List<String> log,
  RecordingHttpOverrides http,
  List<String> launched,
) {
  _outDir.createSync(recursive: true);
  return File('${_outDir.path}/seed-$seed.log')..writeAsStringSync(
    [
      ...log,
      '',
      'Requests (${http.requests.length}):',
      for (final r in http.requests) '  $r',
      if (launched.isNotEmpty) ...['', 'Links opened:', ...launched],
    ].join('\n'),
  );
}

/// Writes the session's log and a picture of the screen it failed on, and
/// prints how to reproduce it.
Future<void> _saveFailure(
  WidgetTester tester,
  int seed,
  List<String> log,
  RecordingHttpOverrides http,
  List<String> launched,
) async {
  final logFile = _writeLog(seed, log, http, launched);
  final shot = File('${_outDir.path}/seed-$seed.png');
  try {
    await tester.runAsync(() async {
      final root = find.byType(MaterialApp).evaluate();
      if (root.isEmpty) return;
      final image = await captureImage(root.first);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) shot.writeAsBytesSync(bytes.buffer.asUint8List());
    });
  } catch (e) {
    // ignore: avoid_print
    print('Monkey: no screenshot ($e)');
  }
  // ignore: avoid_print
  print(
    '\nMonkey session $seed failed. Reproduce it with:\n'
    '  make monkey MONKEY_SEED=$seed MONKEY_SESSIONS=1 MONKEY_STEPS=$_steps\n'
    'Action log: frontend/${logFile.path}\n'
    'Screenshot: frontend/${shot.path}\n',
  );
}

const _imagePicker = MethodChannel('plugins.flutter.io/image_picker');
const _urlLauncher = MethodChannel('plugins.flutter.io/url_launcher');

void _installPlugins(List<String> launched) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  // The user opens the photo picker and cancels it.
  messenger.setMockMethodCallHandler(_imagePicker, (_) async => null);
  // Phone, SMS and attribution links "open" in another app.
  messenger.setMockMethodCallHandler(_urlLauncher, (call) async {
    final url = (call.arguments as Map<Object?, Object?>?)?['url'];
    if (call.method == 'launch') launched.add('$url');
    return true;
  });
}

void _uninstallPlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger
    ..setMockMethodCallHandler(_imagePicker, null)
    ..setMockMethodCallHandler(_urlLauncher, null);
}

/// A device where the user answered the location prompt one way or the
/// other. Granted puts them in Milwaukee, among the seeded friends.
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
