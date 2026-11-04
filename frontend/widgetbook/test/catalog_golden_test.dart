// A golden of every catalog entry, in light and dark.
//
// Each entry opens through the real Widgetbook app in preview mode, so the
// image is exactly what a reviewer sees in the catalog with its knobs at
// their defaults: the same Stage, the same fake blocs, the same addons. Two
// addons are set from the route:
//
// * Theme: Light, then Dark.
// * Reduced motion: on. The Ambient Field drifts and the Chromatic Pulse
//   breathes for as long as they are on screen, so with motion on an image
//   is whichever frame the test reached. Reduced motion is the still
//   composition the app itself shows when the platform asks for it.
//
// clock.now() is pinned to Fixtures.now, the day every fixture date hangs off,
// so the Pulse calendar and recency colours don't move with the real date.
//
// The images live in goldens/, one directory per catalog folder. The last
// test fails on any image no entry produces, so a renamed or deleted entry
// doesn't leave its old picture behind.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_harness/golden_harness.dart';
import 'package:map_my_friends_widgetbook/main.dart';
import 'package:map_my_friends_widgetbook/main.directories.g.dart';
import 'package:map_my_friends_widgetbook/support/fixtures.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'support/catalog.dart';

/// An iPhone 13 window: the size most entries are designed against. At 1x,
/// like the app's own goldens: the Ambient Field behind every entry is a
/// gradient PNG compresses poorly, and at 2x the catalog's images came to
/// almost 90 MB.
const _window = Size(390, 844);
const _pixelRatio = 1.0;

const _themes = ['Light', 'Dark'];

/// Where [path]'s golden in [theme] lives, relative to this file.
String _goldenFor(String path, String theme) {
  final file = path.replaceAll(RegExp(r'[^a-z0-9/-]'), '');
  return 'goldens/$file.${theme.toLowerCase()}.png';
}

bool _isOverflow(FlutterErrorDetails details) =>
    details.exceptionAsString().contains('overflowed by');

void main() {
  setUpGoldens();

  setUpAll(() {
    tz.initializeTimeZones();
    // flutter_map's tile cache asks path_provider for a directory, and a
    // widget test has no platform to answer. Tiles still fail to load
    // (tests have no network), so the map renders blank either way.
    final cache = Directory.systemTemp.createTempSync('catalog_goldens');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => cache.path,
        );
  });

  final paths = useCasePaths(directories);

  for (final path in paths) {
    for (final theme in _themes) {
      goldenTest('$path, ${theme.toLowerCase()}', now: Fixtures.now, (
        tester,
      ) async {
        tester.view.physicalSize = _window * _pixelRatio;
        tester.view.devicePixelRatio = _pixelRatio;
        addTearDown(tester.view.reset);

        // A layout overflow is drawn as the striped warning bar, which the
        // image records, and is listed in the log. With the real typefaces
        // it is a real overflow, unlike the smoke test's. Anything else that
        // throws is the smoke test's to report, with a better message.
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          if (_isOverflow(details)) {
            debugPrint(
              'OVERFLOW $path, ${theme.toLowerCase()}: '
              '${details.exceptionAsString().split('\n').first}',
            );
          } else {
            previous?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = previous);

        await tester.pumpWidget(
          WidgetbookApp(initialRoute: routeTo(path, theme: theme)),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        await expectGolden(
          tester,
          find.byType(WidgetbookApp),
          _goldenFor(path, theme),
        );

        // Run out any timers the entry left (toasts, debounces), so they
        // are not reported against the next one.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }

  test('every golden belongs to a catalog entry', () {
    final expected = {
      for (final path in paths)
        for (final theme in _themes) 'test/${_goldenFor(path, theme)}',
    };
    final directory = Directory('test/goldens');
    final orphans = [
      if (directory.existsSync())
        for (final file in directory.listSync(recursive: true))
          if (file is File && file.path.endsWith('.png'))
            if (!expected.contains(file.path)) file.path,
    ]..sort();
    expect(
      orphans,
      isEmpty,
      reason:
          'no catalog entry renders these any more; delete them, or rename '
          'them to match the entry that replaced them',
    );
  });
}
