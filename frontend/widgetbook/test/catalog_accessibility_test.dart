// Checks every catalog entry against the accessibility bar
// lib/utils/a11y_constants.dart sets, with the app's real fonts:
//
// * Tap targets: at least 48x48, Android's minimum and the larger of the
//   two platforms'.
// * Labels: every tappable node has a label or tooltip, so a screen reader
//   can name it.
// * Large text: nothing overflows with the system text size at 200%, the
//   largest the catalog's Text scale addon offers and what WCAG 1.4.4 asks
//   text to survive.
//
// Text contrast is checked in catalog_contrast_test.dart, with the test
// font. A layout check needs the real typefaces (the test font is much
// wider), and a contrast check reads the colours under each glyph, which
// real glyphs' antialiased edges muddy.
//
// Problems with a task are listed in support/accessibility_gaps.dart.
// Entries open as the catalog shows them, with motion reduced, so these are
// the first frame a reviewer sees, not what an entry shows after a tap.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_harness/golden_harness.dart';
import 'package:map_my_friends_widgetbook/main.directories.g.dart';

import 'support/accessibility.dart';
import 'support/accessibility_gaps.dart';
import 'support/catalog.dart';

bool _isOverflow(FlutterErrorDetails details) =>
    details.exceptionAsString().contains('overflowed by');

/// An overflow as one line, with the widget that overflowed.
String _describeOverflow(FlutterErrorDetails details) {
  final what = details.exceptionAsString().split('\n').first;
  final where = RegExp(
    r'lib/\S+:\d+:\d+',
  ).firstMatch(details.toString())?.group(0);
  return where == null ? what : '$what ($where)';
}

void main() {
  setUpCatalog();
  // Real fonts, on every platform: layout depends only on the font files,
  // unlike the pixels goldens compare.
  setUpAll(loadRealFonts);

  final paths = useCasePaths(directories);

  test('every known gap names a catalog entry', () {
    final stale = [
      for (final key in [
        ...tapTargetGaps.keys,
        ...labelGaps.keys,
        ...largeTextGaps.keys,
      ])
        if (!paths.contains(key)) key,
    ];
    expect(stale, isEmpty, reason: 'no catalog entry has these paths');
  });

  for (final path in paths) {
    testWidgets('$path: tap targets', (tester) async {
      await openEntry(tester, routeTo(path, theme: 'Light'));
      final issues = await issuesFound(tester, androidTapTargetGuideline);
      await closeEntry(tester);

      expectKnownGaps(
        issues,
        gaps: tapTargetGaps,
        key: path,
        check: 'the tap target check',
      );
    });

    testWidgets('$path: labels', (tester) async {
      await openEntry(tester, routeTo(path, theme: 'Light'));
      final issues = await issuesFound(tester, labeledTapTargetGuideline);
      await closeEntry(tester);

      expectKnownGaps(
        issues,
        gaps: labelGaps,
        key: path,
        check: 'the label check',
      );
    });

    testWidgets('$path: text at 200%', (tester) async {
      final errors = await openEntry(
        tester,
        routeTo(path, theme: 'Light', textScale: 2.0),
      );
      // Described before the tree goes: the description reads the render
      // objects that overflowed.
      final overflows = errors.where(_isOverflow).map(_describeOverflow);
      final issues = overflows.toList();
      await closeEntry(tester);

      expectKnownGaps(
        issues,
        gaps: largeTextGaps,
        key: path,
        check: 'text at 200%',
      );
    });
  }
}
