// The shell at each device class it ships to, as a picture: navigation rail
// or bar, the Ambient Field, and the glass over it. The layout tests in
// shell_adaptation_test.dart assert the same sizes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_harness/golden_harness.dart';
import 'package:map_my_friends/main.dart';

import '../helpers/shell_harness.dart';

void main() {
  setUpGoldens();

  late ShellHarness shell;

  setUpAll(ShellHarness.registerFallbacks);
  setUp(() => shell = ShellHarness());

  for (final entry in <String, Size>{
    'phone_portrait': phonePortrait,
    'phone_landscape': phoneLandscape,
    'tablet_portrait': tabletPortrait,
    'tablet_landscape': tabletLandscape,
  }.entries) {
    goldenTest('shell on ${entry.key}', (tester) async {
      await shell.pump(tester, entry.value);
      await expectGolden(
        tester,
        find.byType(MainScreen),
        'goldens/shell_${entry.key}.png',
      );
    });
  }
}
