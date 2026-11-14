import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends_widgetbook/main.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'accessibility_gaps.dart';

/// An iPhone 13 window, as the catalog goldens use: the size most entries
/// are designed against.
const catalogWindow = Size(390, 844);

/// What every accessibility test file sets up once: time zones for the
/// screens that show a friend's local time, and a tile cache directory for
/// flutter_map, which asks path_provider for one.
void setUpCatalog() {
  setUpAll(() {
    tz.initializeTimeZones();
    final cache = Directory.systemTemp.createTempSync('catalog_a11y');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => cache.path,
        );
  });
}

SemanticsHandle? _semantics;

/// Opens [route] through the real catalog app, with semantics on until
/// [closeEntry], and returns what it reported to [FlutterError.onError] while building.
///
/// Errors are collected rather than thrown: the smoke test is the one that
/// fails an entry for throwing, and the large-text check wants the layout
/// overflows as findings.
Future<List<FlutterErrorDetails>> openEntry(
  WidgetTester tester,
  String route,
) async {
  tester.view.physicalSize = catalogWindow;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _semantics = tester.ensureSemantics();

  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await tester.pumpWidget(WidgetbookApp(initialRoute: route));
    // Not pumpAndSettle: the Ambient Field and the Chromatic Pulse animate
    // for as long as they are on screen, so nothing settles.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

/// Tears the entry down inside the test, then runs out any timers it left
/// (toasts, debounces), so they are not reported against the next one.
///
/// Call it before any expectation: flutter_test checks that semantics were
/// turned off again before it runs a test's tear-downs.
Future<void> closeEntry(WidgetTester tester) async {
  _semantics?.dispose();
  _semantics = null;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

/// Each problem [guideline] finds on screen, one string per semantics node,
/// as flutter_test describes it.
Future<List<String>> issuesFound(
  WidgetTester tester,
  AccessibilityGuideline guideline,
) async {
  final evaluation = await guideline.evaluate(tester);
  if (evaluation.passed) return const [];
  return (evaluation.reason ?? '')
      .split(RegExp(r'^(?=SemanticsNode#)', multiLine: true))
      .map((issue) => issue.trim())
      .where((issue) => issue.isNotEmpty)
      .where((issue) => !_isEmojiOnly(issue))
      .toList();
}

/// Whether [issue] is about a node whose label has no letters or digits.
///
/// Contrast is measured on text, and an emoji (a friend's pin) is a picture
/// drawn by the text engine: its colours are the emoji's own, so a ratio
/// between them says nothing about whether it can be seen.
bool _isEmojiOnly(String issue) {
  final label = RegExp(r'label: "([^"]*)"').firstMatch(issue)?.group(1);
  return label != null &&
      label.isNotEmpty &&
      !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(label);
}

/// Fails unless [issues] is exactly what [gaps] records for [key]: none, if
/// it records nothing.
///
/// A known gap is a count, not a pass: a new problem in an entry that
/// already has one still fails, and so does fixing one, so the list never
/// claims more than is still wrong.
void expectKnownGaps(
  List<String> issues, {
  required Map<String, KnownGap> gaps,
  required String key,
  required String check,
}) {
  final gap = gaps[key];
  final expected = gap?.issues ?? 0;
  if (issues.length == expected) return;

  final found = issues.join('\n\n');
  if (expected == 0) {
    fail('$key: $check found ${issues.length} problem(s):\n\n$found');
  }
  if (issues.length < expected) {
    fail(
      '$key: $check found ${issues.length} problem(s), but '
      'accessibility_gaps.dart records $expected for ${gap!.task}. If you '
      'fixed some, lower the count there (or remove the entry).\n\n$found',
    );
  }
  fail(
    '$key: $check found ${issues.length} problem(s). '
    'accessibility_gaps.dart records $expected for ${gap!.task}; '
    'the rest are new.\n\n$found',
  );
}
