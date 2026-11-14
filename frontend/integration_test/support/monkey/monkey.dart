// The monkey: a seeded random user who taps, drags, pinches, types and
// presses back as fast as the app will let them, failing on the first
// exception, layout overflow or broken frame.
//
// Shared by the widget-test monkey (test/monkey/app_monkey_test.dart), which
// runs the real app over an in-memory API, the edge-case tests
// (test/edge_cases), and the device-level monkey
// (integration_test/monkey_test.dart), which runs it on the real web engine
// against the E2E stack. It lives here because a web build can only import
// what's under integration_test/, and it sticks to flutter_test, never
// dart:io, so it compiles for the web.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'known_gaps.dart';

/// One kind of thing the monkey can do, and how often it does it relative
/// to the others.
class MonkeyAction {
  const MonkeyAction(this.name, this.weight, this.run);

  final String name;
  final int weight;

  /// Does the thing and returns what it did, for the log (e.g. "tap
  /// (120, 433) on IconButton"). Returns null when there was nothing to do
  /// it to (no text field on screen, say); the monkey then picks again.
  final Future<String?> Function(Monkey monkey) run;
}

/// What the screen must never be: checked after every action.
typedef MonkeyInvariant = String? Function(WidgetTester tester);

/// Window sizes the monkey switches between: the phone and tablet classes
/// the app ships to, in both orientations, and a narrow one.
const monkeyWindows = <Size>[
  Size(390, 844),
  Size(844, 390),
  Size(667, 375),
  Size(834, 1112),
  Size(1112, 834),
  Size(1280, 720),
  Size(320, 568),
];

/// Text the monkey types. Each entry is something real people type, or that
/// a real form must survive: very long input, emoji (including ones built
/// from several code points), right-to-left and combining scripts,
/// characters that mean something to HTML, SQL, URLs or format strings,
/// whitespace-only, and numbers where words go.
const monkeyText = <String>[
  '',
  ' ',
  '   \t  ',
  'a',
  'Grace',
  'Hopper',
  'Milwaukee',
  'USA',
  '2015550123',
  '+44 20 7946 0958',
  '1906-12-09',
  'not-a-date',
  '0',
  '-1',
  '99999999999999999999',
  '3.14159',
  '🦄',
  '👩🏽‍💻🇮🇪👨‍👩‍👧‍👦',
  'Zoë Ñúñez-Ångström',
  'نور الهدى',
  'שלום עולם',
  '李小龍',
  'e\u0301\u0301\u0301',
  "Robert'); DROP TABLE people;--",
  '<script>alert(1)</script>',
  '%s%s%n{0}{{x}}',
  r'C:\Users\..\..\etc\passwd',
  'http://example.com/?q=a&b=c#frag',
  'Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch',
  'line one\nline two\nline three',
];

/// A long string, built rather than written out: 2,000 characters.
final monkeyLongText = List.filled(200, 'Wolfeschl ').join();

/// The seeded random user. Construct one per app session.
class Monkey {
  Monkey(
    this.tester, {
    required this.seed,
    this.windows = monkeyWindows,
    this.avoid = const [],
    this.extraActions = const [],
    this.invariants = const [],
    this.knownGaps = const [],
    this.survey = false,
    this.recover,
    this.actionTimeout = const Duration(seconds: 60),
    this.onRecord,
  }) : random = Random(seed),
       errors = ErrorWatch(knownGaps);

  final WidgetTester tester;
  final int seed;
  final Random random;
  final List<Size> windows;

  /// Widgets the monkey must never touch, e.g. a button that would leave the
  /// app for a hosted login page. Random-point taps that would land on one
  /// are skipped.
  final List<Finder> avoid;

  /// More actions, for what only one harness can do (e.g. switching the
  /// fake network offline).
  final List<MonkeyAction> extraActions;

  /// Checked after every action, as well as "no exception".
  final List<MonkeyInvariant> invariants;

  /// Filed problems: logged and counted when they recur, not failed.
  final List<KnownGap> knownGaps;

  /// Every error the app reports while the monkey runs.
  final ErrorWatch errors;

  /// Keep going past problems, collecting each distinct one in [findings],
  /// instead of failing on the first. For triage, not for CI.
  final bool survey;

  /// Distinct problems seen in [survey] mode, by [signature]: the first
  /// report and the steps it happened at.
  final Map<String, ({String report, List<String> steps})> findings = {};

  /// The window and text size now, for a finding's context.
  String get conditions =>
      '${window.width.toInt()}×${window.height.toInt()}, text ×$textScale';

  /// What makes two reports the same problem: the error's first line with
  /// numbers blanked (so "overflowed by 20 pixels" and "by 31 pixels"
  /// match), and the first place in the app's own code it names.
  static String signature(String report) {
    final lines = report.split('\n');
    final message = lines.firstWhere(
      (l) =>
          l.trim().isNotEmpty &&
          !l.contains('EXCEPTION CAUGHT') &&
          !l.startsWith('The following'),
      orElse: () => '',
    );
    final where = RegExp(
      r'(lib/|package:map_my_friends/)[\w/]+\.dart:\d+',
    ).firstMatch(report)?.group(0);
    final first = RegExp(r'\d+(\.\d+)?').allMatches(message).isEmpty
        ? message
        : message.replaceAll(RegExp(r'\d+(\.\d+)?'), 'N');
    return '${first.trim()} @ ${where ?? '?'}';
  }

  /// How often each known gap came up this session.
  final Map<KnownGap, int> knownGapHits = {};

  /// Called every step. If the app is somewhere the monkey can't leave by
  /// random input (signed out, say), it gets it back and returns what it
  /// did, for the log. Returns null otherwise.
  final Future<String?> Function(Monkey monkey)? recover;

  /// Called with each log entry as it's written, e.g. to send it somewhere
  /// that survives a hang.
  final void Function(String entry)? onRecord;

  /// How long one action (and the frames after it) may take before the app
  /// counts as hung. The slowest action waits about 5 seconds.
  final Duration actionTimeout;

  /// Every action so far, numbered: the reproduction.
  final List<String> log = [];

  int _step = 0;
  int get step => _step;

  double get textScale => tester.platformDispatcher.textScaleFactor;

  Size get window => tester.view.physicalSize / tester.view.devicePixelRatio;

  late final List<MonkeyAction> actions = [
    MonkeyAction('tap a control', 30, _tapControl),
    MonkeyAction('tap anywhere', 12, _tapAnywhere),
    MonkeyAction('double tap', 4, _doubleTap),
    MonkeyAction('long press', 4, _longPress),
    MonkeyAction('rapid taps', 4, _rapidTaps),
    MonkeyAction('two-finger tap', 2, _twoFingerTap),
    MonkeyAction('drag', 8, _drag),
    MonkeyAction('fling', 3, _fling),
    MonkeyAction('pinch', 4, _pinch),
    MonkeyAction('type', 10, _type),
    MonkeyAction('submit', 2, _submit),
    MonkeyAction('back', 5, _back),
    MonkeyAction('switch tab', 6, _switchTab),
    MonkeyAction('wait', 3, _wait),
    MonkeyAction('background and resume', 1, _lifecycle),
    MonkeyAction('resize window', 1, _resize),
    MonkeyAction('change text size', 1, _textScale),
    ...extraActions,
  ];

  late final int _totalWeight = actions.fold(0, (sum, a) => sum + a.weight);

  /// Runs [steps] actions, or until [until] (real time) passes, whichever
  /// comes first. Fails with the seed and the action log on the first
  /// problem.
  Future<void> run({required int steps, DateTime? until}) async {
    errors.start();
    for (var i = 0; i < steps; i++) {
      if (until != null && DateTime.now().isAfter(until)) break;
      await act();
    }
  }

  /// Lets whatever the last actions started finish, then checks once more,
  /// so a late error is still this session's.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    _check();
  }

  /// One action, then the checks.
  Future<void> act() async {
    _step++;
    final recovered = await _guard(
      'recovering',
      () async => recover?.call(this),
    );
    if (recovered != null) {
      _record('recover: $recovered');
      await _guard('settling after recovery', _frames);
      _check();
    }
    for (var attempt = 0; attempt < 10; attempt++) {
      final action = _pick();
      onRecord?.call('$_step. (starting: ${action.name})');
      final did = await _guard(action.name, () => action.run(this));
      if (did == null) continue;
      _record(did);
      await _guard('settling after "$did"', _frames);
      _check();
      return;
    }
    _record('nothing to do');
    await _guard('settling', _frames);
    _check();
  }

  /// Runs [body], failing as a hang if it takes longer than [actionTimeout].
  /// A hung app otherwise just stalls the run until the job's timeout, with
  /// nothing to say which action it was.
  Future<T> _guard<T>(String what, Future<T> Function() body) => body().timeout(
    actionTimeout,
    onTimeout: () => _fail(
      'hung: "$what" did not finish within ${actionTimeout.inSeconds} s',
    ),
  );

  MonkeyAction _pick() {
    var roll = random.nextInt(_totalWeight);
    for (final action in actions) {
      if ((roll -= action.weight) < 0) return action;
    }
    return actions.last;
  }

  void _record(String entry) {
    final line = '$_step. $entry';
    log.add(line);
    onRecord?.call(line);
  }

  /// Lets the action's consequences play out: a random wait, so taps land
  /// at every point of a request, a route transition or an animation.
  Future<void> _frames() async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: random.nextInt(400)));
    await tester.pump(const Duration(milliseconds: 16));
  }

  void _check() {
    for (final problem in errors.take(tester)) {
      final gap = problem.gap;
      if (gap != null) {
        knownGapHits.update(gap, (n) => n + 1, ifAbsent: () => 1);
        _record('known gap, ${gap.what} (${gap.task})');
        continue;
      }
      if (survey) {
        final key = signature(problem.report);
        findings
            .putIfAbsent(key, () => (report: problem.full, steps: []))
            .steps
            .add('$_step ($conditions)');
        _record('PROBLEM: $key');
        continue;
      }
      _fail('threw ${problem.type}:\n${problem.report}');
    }
    for (final invariant in invariants) {
      final problem = invariant(tester);
      if (problem != null) _fail(problem);
    }
  }

  Never _fail(String problem) {
    final tail = log.length > 60 ? log.sublist(log.length - 60) : log;
    fail(
      'Monkey (seed $seed) found a problem at step $_step: $problem\n\n'
      'Last ${tail.length} of ${log.length} actions:\n'
      '${tail.map((l) => '  $l').join('\n')}\n',
    );
  }

  // ------------------------------------------------------------------------
  // Picking where to act
  // ------------------------------------------------------------------------

  /// Anything a finger can operate. Hit-testable only, so nothing hidden
  /// behind a sheet or off the screen.
  static final Finder controls = find
      .byWidgetPredicate(
        (w) =>
            w is InkResponse ||
            w is ButtonStyleButton ||
            w is IconButton ||
            w is FloatingActionButton ||
            w is EditableText ||
            w is Checkbox ||
            w is Radio<Object?> ||
            w is Switch ||
            w is Slider ||
            w is RawChip ||
            w is SegmentedButton<Object?> ||
            w is PopupMenuButton<Object?> ||
            w is DropdownButton<Object?> ||
            (w is GestureDetector &&
                (w.onTap != null || w.onLongPress != null)),
        description: 'a control',
      )
      .hitTestable();

  T _any<T>(List<T> items) => items[random.nextInt(items.length)];

  Offset _randomPoint({double margin = 2}) => Offset(
    margin + random.nextDouble() * (window.width - 2 * margin),
    margin + random.nextDouble() * (window.height - 2 * margin),
  );

  static String _round(Offset o) =>
      '(${o.dx.toStringAsFixed(0)}, ${o.dy.toStringAsFixed(0)})';

  bool _avoided(Offset point) {
    for (final finder in avoid) {
      for (final element in finder.evaluate()) {
        final box = element.renderObject;
        if (box is RenderBox && box.hasSize && box.attached) {
          final rect = box.localToGlobal(Offset.zero) & box.size;
          if (rect.inflate(4).contains(point)) return true;
        }
      }
    }
    return false;
  }

  /// A random control's centre, with its type for the log.
  (Offset, String)? _randomControl() {
    final elements = controls.evaluate().toList();
    final candidates = <(Offset, String)>[];
    for (final element in elements) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      if (!(Offset.zero & window).contains(center) || _avoided(center)) {
        continue;
      }
      candidates.add((center, _describe(element)));
    }
    return candidates.isEmpty ? null : _any(candidates);
  }

  /// The control's type and, when it has one, its label or text.
  static String _describe(Element element) {
    final widget = element.widget;
    String? label;
    final texts = <String>[];
    void collect(Element e) {
      final w = e.widget;
      if (w is Text && w.data != null) texts.add(w.data!);
      if (w is Icon && w.semanticLabel != null) texts.add(w.semanticLabel!);
      if (w is Tooltip && w.message != null) texts.add(w.message!);
      if (texts.length < 2) e.visitChildElements(collect);
    }

    collect(element);
    if (widget is IconButton) label = widget.tooltip;
    label ??= texts.isEmpty ? null : texts.join(' / ');
    final type = widget.runtimeType.toString().replaceAll(RegExp('<.*>'), '');
    if (label == null) return type;
    final short = label.length > 40 ? '${label.substring(0, 40)}…' : label;
    return '$type "${short.replaceAll('\n', ' ')}"';
  }

  // ------------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------------

  Future<String?> _tapControl(Monkey _) async {
    final target = _randomControl();
    if (target == null) return null;
    final (point, what) = target;
    await tester.tapAt(point);
    return 'tap $what at ${_round(point)}';
  }

  Future<String?> _tapAnywhere(Monkey _) async {
    final point = _randomPoint();
    if (_avoided(point)) return null;
    await tester.tapAt(point);
    return 'tap ${_round(point)}';
  }

  Future<String?> _doubleTap(Monkey _) async {
    final target = random.nextBool() ? _randomControl() : null;
    final point = target?.$1 ?? _randomPoint();
    if (_avoided(point)) return null;
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(point);
    return 'double tap ${target?.$2 ?? ''} at ${_round(point)}'.trim();
  }

  Future<String?> _longPress(Monkey _) async {
    final target = random.nextBool() ? _randomControl() : null;
    final point = target?.$1 ?? _randomPoint();
    if (_avoided(point)) return null;
    await tester.longPressAt(point);
    return 'long press ${target?.$2 ?? ''} at ${_round(point)}'.trim();
  }

  /// The same control, five times, as fast as a frustrated user: double
  /// submits, double pushes, double deletes.
  Future<String?> _rapidTaps(Monkey _) async {
    final target = _randomControl();
    if (target == null) return null;
    final (point, what) = target;
    for (var i = 0; i < 5; i++) {
      await tester.tapAt(point);
      await tester.pump(Duration(milliseconds: random.nextInt(30)));
    }
    return '5 rapid taps on $what at ${_round(point)}';
  }

  /// Two fingers down at once, on two different places.
  Future<String?> _twoFingerTap(Monkey _) async {
    final a = _randomControl()?.$1 ?? _randomPoint();
    final b = _randomPoint();
    if (_avoided(a) || _avoided(b)) return null;
    final first = await tester.startGesture(a);
    final second = await tester.startGesture(b);
    await tester.pump(const Duration(milliseconds: 40));
    await first.up();
    await second.up();
    return 'two-finger tap ${_round(a)} + ${_round(b)}';
  }

  Offset _randomDelta(double max) => Offset(
    (random.nextDouble() * 2 - 1) * max,
    (random.nextDouble() * 2 - 1) * max,
  );

  Future<String?> _drag(Monkey _) async {
    final from = _randomPoint(margin: 8);
    if (_avoided(from)) return null;
    final by = _randomDelta(window.shortestSide * 0.6);
    await tester.dragFrom(from, by);
    return 'drag ${_round(from)} by ${_round(by)}';
  }

  Future<String?> _fling(Monkey _) async {
    final from = _randomPoint(margin: 8);
    if (_avoided(from)) return null;
    final by = _randomDelta(window.shortestSide * 0.5);
    await tester.flingFrom(from, by, 1500 + random.nextDouble() * 2500);
    return 'fling ${_round(from)} by ${_round(by)}';
  }

  /// Two fingers moving apart (zoom in) or together (zoom out), as on the
  /// map, though anywhere is fair game.
  Future<String?> _pinch(Monkey _) async {
    final center = _randomPoint(margin: 60);
    final spread = 20 + random.nextDouble() * 60;
    final out = random.nextBool();
    final axis = Offset.fromDirection(random.nextDouble() * pi);
    final a = center - axis * spread;
    final b = center + axis * spread;
    if (_avoided(a) || _avoided(b)) return null;
    final first = await tester.startGesture(a);
    final second = await tester.startGesture(b);
    final stepBy = axis * (out ? 6.0 : -4.0);
    for (var i = 0; i < 8; i++) {
      await first.moveBy(-stepBy);
      await second.moveBy(stepBy);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    return 'pinch ${out ? 'out' : 'in'} at ${_round(center)}';
  }

  String _randomText() {
    final roll = random.nextInt(20);
    if (roll == 0) return monkeyLongText;
    if (roll == 1) {
      // Two entries run together, so odd combinations come up too.
      return _any(monkeyText) + _any(monkeyText);
    }
    return _any(monkeyText);
  }

  Finder get _textFields => find.byType(EditableText).hitTestable();

  Future<String?> _type(Monkey _) async {
    final fields = _textFields.evaluate().toList();
    if (fields.isEmpty) return null;
    final element = _any(fields);
    final box = element.renderObject;
    if (box is! RenderBox || !box.attached) return null;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    if (_avoided(center)) return null;
    final text = _randomText();
    if (!tester.testTextInput.isRegistered) return null;
    final finder = find.byElementPredicate((e) => e == element);
    await tester.showKeyboard(finder);
    tester.testTextInput.enterText(text);
    await tester.pump();
    final hint = (element.widget as EditableText).controller.text;
    final shown = text.length > 30
        ? '${text.substring(0, 30)}… (${text.length} chars)'
        : text;
    return 'type ${_quote(shown)} into field at ${_round(center)}'
        '${hint == text ? '' : ' (field kept ${hint.length} chars)'}';
  }

  static String _quote(String s) => '"${s.replaceAll('\n', r'\n')}"';

  /// The keyboard's action key (Done, Next, Search) in whatever field has
  /// focus.
  Future<String?> _submit(Monkey _) async {
    final input = tester.testTextInput;
    if (!input.isRegistered || !input.isVisible) return null;
    final action = _any(const [
      TextInputAction.done,
      TextInputAction.next,
      TextInputAction.search,
      TextInputAction.go,
    ]);
    await tester.testTextInput.receiveAction(action);
    return 'press ${action.name} on the keyboard';
  }

  /// The system back button (Android's, the browser's): it pops whatever
  /// is on top, or asks to leave the app.
  Future<String?> _back(Monkey _) async {
    // On the web, back with nothing left to pop is the browser's Back button:
    // it navigates the page away from the app, which ends the run (the test
    // dies with the page, so nothing reports). Leaving the app isn't the
    // monkey's job, so there it only goes back while a route can pop.
    if (kIsWeb &&
        !tester
            .stateList<NavigatorState>(find.byType(Navigator))
            .any((navigator) => navigator.canPop())) {
      return null;
    }
    // The message the engine sends for the back button, through the same
    // channel, so the app handles it exactly as on a device.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      SystemChannels.navigation.codec.encodeMethodCall(
        const MethodCall('popRoute'),
      ),
      (_) {},
    );
    return 'system back';
  }

  static final Finder _tabs = find.bySemanticsLabel(
    RegExp(r'^(Map|People|Pulse|Trips|Me) Tab'),
  );

  Future<String?> _switchTab(Monkey _) async {
    final tabs = _tabs.hitTestable().evaluate().toList();
    if (tabs.isEmpty) return null;
    final element = _any(tabs);
    final box = element.renderObject;
    if (box is! RenderBox || !box.attached) return null;
    final point = box.localToGlobal(box.size.center(Offset.zero));
    await tester.tapAt(point);
    return 'switch to ${_describe(element)}';
  }

  Future<String?> _wait(Monkey _) async {
    final ms = 500 + random.nextInt(2500);
    await tester.pump(Duration(milliseconds: ms));
    return 'wait ${ms}ms';
  }

  /// Home button and back: through every lifecycle state, as the OS sends
  /// them, with a random time away.
  Future<String?> _lifecycle(Monkey _) async {
    final binding = tester.binding;
    // On a live binding (the web monkey), hidden and paused stop the engine
    // scheduling frames, so a pump while away would wait for a frame that
    // never comes. There, time away passes in real time and frames resume
    // with the app. The widget-test binding forces frames either way.
    final live = binding is LiveTestWidgetsFlutterBinding;
    Future<void> away(Duration time) =>
        live ? Future<void>.delayed(time) : tester.pump(time);
    const leaving = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    for (final state in leaving) {
      binding.handleAppLifecycleStateChanged(state);
      await away(Duration.zero);
    }
    final ms = random.nextInt(5000);
    await away(Duration(milliseconds: ms));
    for (final state in leaving.reversed.skip(1)) {
      binding.handleAppLifecycleStateChanged(state);
      await away(Duration.zero);
    }
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    return 'background for ${ms}ms, then resume';
  }

  /// A new window size: a rotation, a split screen, a desktop resize.
  Future<String?> _resize(Monkey _) async {
    final size = _any(windows);
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    return 'resize to ${size.width.toInt()}×${size.height.toInt()}';
  }

  Future<String?> _textScale(Monkey _) async {
    final scale = _any(const [1.0, 1.0, 1.3, 2.0]);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    return 'text size ×$scale';
  }

  /// Puts the window back the way the harness set it up, for the next
  /// session. Call from the harness's tear-down.
  void reset() {
    errors.stop();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    if (tester.testTextInput.isRegistered) tester.testTextInput.hide();
  }
}

/// One error the app reported, described while its widget was still live.
class Problem {
  Problem(this.type, this.report, this.full, this.gap);

  final String type;

  /// The description up to the stack trace, plus the app's own frames.
  final String report;

  /// Everything Flutter said, stack included.
  final String full;

  /// The filed task this is, if any.
  final KnownGap? gap;
}

/// Collects every error Flutter reports, and tells filed ones ([knownGaps])
/// from new ones.
///
/// It takes errors over from the test binding, which keeps only the first
/// of several and only its exception. Each is described the moment it's
/// reported, while the widget that raised it is still in the tree:
/// described later, the inspector walks the ancestors of an element that
/// has since been deactivated (itself an assertion) and loses the error's
/// source line.
class ErrorWatch {
  ErrorWatch(this.knownGaps);

  final List<KnownGap> knownGaps;
  final List<({String type, String report, String full})> _seen = [];
  FlutterExceptionHandler? _bindingHandler;

  /// Starts collecting. Call [stop] before the test ends: the binding checks
  /// its handler is back.
  void start() {
    if (_bindingHandler != null) return;
    _bindingHandler = FlutterError.onError;
    FlutterError.onError = (details) => _seen.add(_capture(details));
  }

  void stop() {
    if (_bindingHandler == null) return;
    FlutterError.onError = _bindingHandler;
    _bindingHandler = null;
  }

  /// Every error since the last call, each matched against [knownGaps] at
  /// the current text size.
  List<Problem> take(WidgetTester tester) {
    final seen = [..._seen];
    _seen.clear();
    final pending = tester.takeException();
    if (pending != null) {
      seen.add(_capture(FlutterErrorDetails(exception: pending as Object)));
    }
    final scale = tester.platformDispatcher.textScaleFactor;
    return [
      for (final (:type, :report, :full) in seen)
        Problem(
          type,
          report,
          full,
          knownGaps.where((g) => g.matches(report, scale)).firstOrNull,
        ),
    ];
  }

  /// Fails on any error since the last call that isn't a known gap.
  void expectNone(WidgetTester tester) {
    final unexpected = take(tester).where((p) => p.gap == null).toList();
    if (unexpected.isNotEmpty) {
      fail(
        '${unexpected.length} unexpected error(s):\n\n'
        '${unexpected.map((p) => '${p.type}:\n${p.report}').join('\n\n')}',
      );
    }
  }

  static ({String type, String report, String full}) _capture(
    FlutterErrorDetails details,
  ) {
    String full;
    try {
      full = details.toString();
    } catch (e) {
      full = '${details.exceptionAsString()}\n(not described: $e)';
    }
    return (
      type: details.exception.runtimeType.toString(),
      report: _report(full, details.stack),
      full: full,
    );
  }

  /// The error's description, up to its stack trace: what overflowed, and
  /// the widget (with its source line) that built it.
  static String _report(String text, StackTrace? trace) {
    final stack = text.indexOf('When the exception was thrown');
    final head = stack < 0 ? text : text.substring(0, stack);
    final lines = head.trim().split('\n');
    // The app's own frames, which say where an assertion came from when the
    // description doesn't (a disposed widget, an async callback).
    final ours = (trace?.toString() ?? '')
        .split('\n')
        .where((l) => l.contains('package:map_my_friends/'))
        .take(8)
        .map((l) => '  $l');
    return [
      ...(lines.length > 40 ? [...lines.take(40), '…'] : lines),
      if (ours.isNotEmpty) ...['App frames:', ...ours],
    ].join('\n');
  }
}
