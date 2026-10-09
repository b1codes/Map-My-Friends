import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The guard on the design system's boundary.
///
/// Every rule here was a real finding, not a hypothetical: the app shipped a
/// complete glass design system and still read as Material 3, because each of
/// these leaked back in one call site at a time and no single edit ever looked
/// wrong on its own. A grep is a crude check, but it is the check that runs on
/// every commit, and drift here is always textual.
///
/// When a rule below genuinely needs an exception, add the file to its
/// allowlist *with the reason*. An unexplained entry is how the ban dies.

final Directory _lib = Directory('lib');

List<File> get _sources => _lib
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Files that may mention [pattern], and why.
typedef Allowlist = Map<String, String>;

void _banned(
  String pattern, {

  /// Matches [pattern] as a whole identifier. Without it `Card(` also
  /// convicts `PersonCard(`, and an over-eager guard gets deleted.
  bool wholeWord = true,
  required String because,
  required String instead,
  Allowlist allow = const <String, String>{},
}) {
  final offenders = <String>[];
  for (final file in _sources) {
    final rel = file.path.replaceAll(r'\', '/');
    if (allow.keys.any(rel.endsWith)) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Prose in a doc comment explaining why something is banned is not a
      // use of it.
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//')) continue;
      final bool hit = wholeWord
          ? RegExp('(?<![A-Za-z0-9_])${RegExp.escape(pattern)}').hasMatch(line)
          : line.contains(pattern);
      if (hit) {
        offenders.add('$rel:${i + 1}  ${line.trim()}');
      }
    }
  }

  expect(
    offenders,
    isEmpty,
    reason:
        '`$pattern` is not part of this app.\n$because\nUse $instead instead.\n\n'
        '${offenders.join('\n')}',
  );
}

void main() {
  test('Material tonal elevation stays out of the depth model', () {
    // DESIGN.md §4. These are Material 3's elevation system; using them to
    // express depth is adopting the model Refractive Depth replaces. 43 of
    // them are what made the app read as Material 3.
    for (final role in <String>[
      'surfaceContainer',
      'outlineVariant',
      'surfaceTint',
    ]) {
      _banned(
        role,
        because: 'It is Material 3 tonal elevation, which DESIGN.md §4 bans.',
        instead:
            'GlassContainer for a panel, or GlassInlay for a row, '
            'field, chip, or well',
      );
    }
  });

  test('loading is the Chromatic Pulse', () {
    _banned(
      'CircularProgressIndicator',
      because:
          'llc-standards/context/chromatic-pulse.md makes the pulse a required '
          'brand signature: waiting is not idle.',
      instead: 'PulseIndicator, or ChromaticPulse inside a sized box',
    );
  });

  test('the app has one navigation chrome', () {
    _banned(
      'AppBar(',
      because:
          'The shell is one glass world with floating chrome. A Material app '
          'bar inside it is a second chrome with its own material and type.',
      instead: 'GlassHeader',
      allow: <String, String>{
        'utils/app_theme.dart':
            'AppBarTheme still neutralises the Material defaults for any '
            'framework surface that mounts one.',
        'screens/trips/trip_details_screen.dart':
            'A transparent AppBar carrying only a floating glass back button '
            'over the route map. A full header bar would cover the map this '
            'screen exists to show.',
      },
    );
  });

  test('depth is never a Material card', () {
    _banned(
      'Card(',
      because:
          'A Card is an opaque tonal step standing in for depth that '
          'DESIGN.md §4 resolves optically.',
      instead: 'GlassContainer or GlassInlay',
      allow: <String, String>{
        'utils/app_theme.dart':
            'CardThemeData points any framework-mounted card at the inlay.',
      },
    );
  });

  test('transient messages are glass', () {
    _banned(
      'showSnackBar',
      because:
          'A raw SnackBar is a Material tonal toast; feedback is a brand '
          'moment and this one belonged to Google.',
      instead: 'GlassToast.show / .success / .failure',
      allow: <String, String>{
        'components/shared/glass_surfaces.dart':
            'GlassToast routes through ScaffoldMessenger on purpose, for its '
            'queueing and dismissal.',
      },
    );
  });

  test('confirmation is a GlassDialog', () {
    _banned(
      'AlertDialog',
      because:
          'AlertDialog gives a destructive action the same weight as its '
          'cancel, which turns a delete confirmation into a coin flip.',
      instead: 'GlassDialog.confirm or GlassDialog.panel',
    );
  });

  test('the floating action button stays retired', () {
    _banned(
      'FloatingActionButton',
      because:
          "It is Material's single most recognisable element, and it "
          'collided with the glass nav bar it had to be offset around.',
      instead: 'a HeaderAction on the surface\'s GlassHeader',
    );
  });

  test('every glass radius comes from the scale', () {
    // DESIGN.md rounded: sm 8 / md 16 / lg 30, plus the named pill exception.
    // The app's most common radius used to be 12 — Material's default card
    // radius, and a value this design system does not define.
    final offenders = <String>[];
    final literal = RegExp(r'BorderRadius\.circular\(\s*(\d+(?:\.\d+)?)\s*\)');
    for (final file in _sources) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final match in literal.allMatches(lines[i])) {
          final value = double.parse(match.group(1)!);
          // Sub-scale details — hairline meters, drag handles — are not
          // surfaces and do not take a surface radius.
          if (value <= 4) continue;
          offenders.add('${file.path}:${i + 1}  radius ${match.group(1)}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use MapGlass.radiusSm / radiusMd / radiusLg / radiusPill.\n\n'
          '${offenders.join('\n')}',
    );
  });
}
