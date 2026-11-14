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
import 'package:flutter_test/flutter_test.dart';

import '../helpers/recording_http_overrides.dart';
import 'app_session.dart';
import '../../integration_test/support/monkey/known_gaps.dart';
import '../../integration_test/support/monkey/monkey.dart';

/// The seed the PR run uses, so it's the same run every time. 'random'
/// draws one (the nightly run); either way it's printed.
const _seedDefine = String.fromEnvironment(
  'MONKEY_SEED',
  defaultValue: '20261108',
);

/// App launches per run, and actions per launch.
const _sessions = int.fromEnvironment('MONKEY_SESSIONS', defaultValue: 12);
const _steps = int.fromEnvironment('MONKEY_STEPS', defaultValue: 250);

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

/// Off unless asked for: see the library comment.
const _enabled = bool.fromEnvironment('MONKEY');

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    // Real fonts, and one network for every session, so a seed replays
    // alone exactly as it ran in the batch (see app_session.dart).
    await setUpAppSessions();
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
      // Hangs fail rather than stall CI: a session of 250 actions takes
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
  final located = random.nextBool();
  final window = monkeyWindows[random.nextInt(monkeyWindows.length)];
  final session = await AppSession.start(
    tester,
    window: window,
    located: located,
    seed: seed,
  );
  final api = session.api;
  final http = session.http;
  final launched = session.launched;

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
    session.restore(tester);
    semantics.dispose();
  }
  await AppSession.unmount(tester);
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
