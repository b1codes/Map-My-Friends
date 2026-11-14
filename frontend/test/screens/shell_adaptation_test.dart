import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/shell_harness.dart';

// The goldens of the same shell are in shell_golden_test.dart.

void main() {
  late ShellHarness shell;

  setUpAll(ShellHarness.registerFallbacks);
  setUp(() => shell = ShellHarness());

  for (final entry in <String, Size>{
    'phone portrait': phonePortrait,
    'phone landscape': phoneLandscape,
    'small phone landscape': smallPhoneLandscape,
    'tablet portrait': tabletPortrait,
    'tablet landscape': tabletLandscape,
  }.entries) {
    testWidgets('shell lays out without overflow on ${entry.key}', (
      tester,
    ) async {
      await shell.pump(tester, entry.value);

      expect(
        tester.takeException(),
        isNull,
        reason: 'navigation overflowed at ${entry.value}',
      );
    });

    testWidgets('every destination is reachable on ${entry.key}', (
      tester,
    ) async {
      await shell.pump(tester, entry.value);
      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;

      // The rail is a Positioned with only `left` and `top`, so it is
      // vertically unconstrained: it paints past the bottom edge instead of
      // reporting an overflow. Nothing throws, the tabs are simply gone.
      for (final label in ['Map', 'People', 'Pulse', 'Trips', 'Me']) {
        final finder = find.text(label);
        expect(finder, findsOneWidget, reason: '$label tab missing');

        final rect = tester.getRect(finder);
        expect(
          rect.bottom,
          lessThanOrEqualTo(viewport.height),
          reason:
              '$label tab is painted below the ${viewport.height}pt viewport '
              'at ${entry.value} — clipped, unreachable, and silent',
        );
        expect(
          rect.right,
          lessThanOrEqualTo(viewport.width),
          reason: '$label tab is painted past the right edge at ${entry.value}',
        );
      }
    });
  }
}
