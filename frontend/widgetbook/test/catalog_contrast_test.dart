// Checks every catalog entry's text against WCAG AA contrast (4.5:1, or 3:1
// for large text), in light and dark, with and without high contrast.
//
// flutter_test's check samples the pixels behind each text node and takes
// the two dominant colours as text and background. It runs on the test
// font, whose glyphs are solid boxes, so the text colour is exactly the
// colour drawn: real glyphs' antialiased edges would blend it with the
// glass and backdrop behind them. Layout checks, which need the real
// typefaces, are in catalog_accessibility_test.dart.
//
// The check sees what a person sees: text over translucent glass is judged
// against whatever the glass is over. Problems with a task are listed in
// support/accessibility_gaps.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:map_my_friends_widgetbook/main.directories.g.dart';

import 'support/accessibility.dart';
import 'support/accessibility_gaps.dart';
import 'support/catalog.dart';

/// The appearances the app has: each theme, and each with the platform's
/// high-contrast setting on.
const _variants = [
  (theme: 'Light', highContrast: false),
  (theme: 'Dark', highContrast: false),
  (theme: 'Light', highContrast: true),
  (theme: 'Dark', highContrast: true),
];

String _keyFor(String path, ({String theme, bool highContrast}) variant) =>
    '$path (${variant.theme.toLowerCase()}'
    '${variant.highContrast ? ', high contrast' : ''})';

void main() {
  setUpCatalog();
  setUpAll(() {
    // The real theme with the test font: GoogleFonts starts a network fetch
    // the moment a TextStyle is built, which fails offline. See
    // AppTheme.textThemeBuilder.
    AppTheme.textThemeBuilder = (color) => Typography.material2021().black
        .apply(bodyColor: color, displayColor: color);
    AppTheme.resetThemeCache();
  });
  tearDownAll(() {
    AppTheme.textThemeBuilder = AppTheme.buildBrandTextTheme;
    AppTheme.resetThemeCache();
  });

  final paths = useCasePaths(directories);

  test('every known gap names a catalog entry and variant', () {
    final keys = {
      for (final path in paths)
        for (final variant in _variants) _keyFor(path, variant),
    };
    final stale = [
      for (final key in contrastGaps.keys)
        if (!keys.contains(key)) key,
    ];
    expect(stale, isEmpty, reason: 'no catalog entry and variant has these');
  });

  for (final path in paths) {
    for (final variant in _variants) {
      final key = _keyFor(path, variant);
      testWidgets('$key: text contrast', (tester) async {
        await openEntry(
          tester,
          routeTo(
            path,
            theme: variant.theme,
            highContrast: variant.highContrast,
          ),
        );
        final issues = await issuesFound(tester, textContrastGuideline);
        await closeEntry(tester);

        expectKnownGaps(
          issues,
          gaps: contrastGaps,
          key: key,
          check: 'the contrast check',
        );
      });
    }
  }
}
